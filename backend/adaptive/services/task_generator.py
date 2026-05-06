"""Task Generator — creates daily tasks for a milestone via LLM."""

from __future__ import annotations

import asyncio
import json
from datetime import date, timedelta
from uuid import UUID

from backend.adaptive.db import AdaptiveStore
from backend.adaptive.models import MilestoneRow, TaskRow
from backend.adaptive.services.milestone_generator import PlanGenerationError
from backend.lib.llm import chatResponse


TASK_PROMPT = """You are a planning expert. Create daily tasks for this milestone.
Return ONLY valid JSON, no explanation.

Goal: {goal}
Milestone: {milestone_title}
Milestone description: {milestone_description}
Milestone outcome: {milestone_outcome}
Available working days: {working_days_count} days
Daily time commitment: {daily_minutes} minutes per day
Start date: {start_date}

Return this JSON:
{{
  "tasks": [
    {{
      "title": "specific actionable task title",
      "description": "1-2 sentences on exactly what to do",
      "duration_minutes": 30,
      "order_index": 0,
      "day_offset": 0
    }}
  ]
}}

Rules:
- Create exactly {working_days_count} tasks (one per working day)
- Each task must directly build toward the milestone outcome
- Tasks should progress in difficulty — start easy, get harder
- Each task's duration_minutes should fit within the user's {daily_minutes} min/day commitment
- day_offset is how many days from today to schedule (0 = today)
- Only use working days based on schedule, skip non-working days
- Return ONLY valid JSON."""

RETRY_PROMPT = """You previously failed to return valid JSON. You MUST return ONLY a raw JSON object — no markdown fences, no explanation, no extra text. Just the JSON. Try again:

{previous_response}

Return the corrected JSON now."""


# ── Schedule helpers ──────────────────────────────────────────────────────────

# Monday=0 through Sunday=6 (matches Python weekday())
WEEKDAY_SETS: dict[str, set[int]] = {
    "daily": {0, 1, 2, 3, 4, 5, 6},
    "weekdays": {0, 1, 2, 3, 4},
    "3x_week": {0, 2, 4},       # Mon, Wed, Fri
    "weekends": {5, 6},          # Sat, Sun
}


def _working_day_set(schedule_prefs: dict | None) -> set[int]:
    """Return the set of weekday numbers (0=Mon..6=Sun) that are working days."""
    if not schedule_prefs:
        return WEEKDAY_SETS["daily"]

    sched_type = schedule_prefs.get("type", "daily")

    if sched_type == "custom":
        custom_days = schedule_prefs.get("days", [])
        if custom_days:
            return set(int(d) for d in custom_days)
        return WEEKDAY_SETS["daily"]

    return WEEKDAY_SETS.get(sched_type, WEEKDAY_SETS["daily"])


def _count_working_days(start: date, suggested_days: int, working_set: set[int]) -> int:
    """Count how many working days fall within `suggested_days` calendar days from `start`."""
    count = 0
    for offset in range(suggested_days):
        d = start + timedelta(days=offset)
        if d.weekday() in working_set:
            count += 1
    return count


def _date_for_day_offset(start: date, day_offset: int, working_set: set[int]) -> date:
    """
    Convert a working-day offset (0-based) to an actual calendar date,
    skipping non-working days.
    """
    working_count = 0
    current = start
    while True:
        if current.weekday() in working_set:
            if working_count == day_offset:
                return current
            working_count += 1
        current += timedelta(days=1)


# ── LLM helpers ──────────────────────────────────────────────────────────────

def _call_llm(prompt: str) -> str:
    return chatResponse(prompt)


def _clean_llm_response(raw: str) -> str:
    content = raw.strip()
    if content.startswith("```json"):
        content = content[7:]
    elif content.startswith("```"):
        content = content[3:]
    if content.endswith("```"):
        content = content[:-3]
    return content.strip()


def _parse_json_with_retry(raw_prompt: str) -> dict:
    raw = _call_llm(raw_prompt)
    cleaned = _clean_llm_response(raw)

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    retry_prompt = RETRY_PROMPT.format(previous_response=cleaned)
    raw = _call_llm(retry_prompt)
    cleaned = _clean_llm_response(raw)

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise PlanGenerationError(
            f"Task generation failed after retry: {exc}",
            raw_response=cleaned,
        )


# ── Main function ────────────────────────────────────────────────────────────

async def generate_for_milestone(
    milestone_id: str,
    user_id: str,
    db: AdaptiveStore,
) -> list[TaskRow]:
    """
    Generate daily tasks for a milestone.

    1. Fetch milestone, plan, and memory records
    2. Calculate available working days from schedule_prefs
    3. Build LLM prompt and call for task generation
    4. Parse response and create TaskRow records with scheduled dates
    5. Return list of TaskRow
    """
    mid = UUID(milestone_id) if isinstance(milestone_id, str) else milestone_id
    uid = UUID(user_id) if isinstance(user_id, str) else user_id

    # Fetch milestone
    ms_res = db.client.table("milestones").select().eq("id", str(mid)).eq("user_id", str(uid)).execute()
    if not ms_res or not ms_res[1]:
        raise PlanGenerationError(f"Milestone {milestone_id} not found")
    milestone = db._map_milestone(ms_res[1][0])

    # Fetch plan
    plan = db.get_plan(milestone.plan_id)
    if plan is None:
        raise PlanGenerationError(f"Plan {milestone.plan_id} not found")

    # Fetch memory
    mem_id = plan.memory_id or plan.goal_id
    if mem_id is None:
        raise PlanGenerationError(f"Plan {plan.id} has no linked memory")

    memory = db.get_memory(mem_id)
    if memory is None:
        raise PlanGenerationError(f"Memory record {mem_id} not found")

    # Parse memory JSON
    try:
        mem_data = json.loads(memory.value)
    except (json.JSONDecodeError, TypeError) as exc:
        raise PlanGenerationError(f"Failed to parse memory JSON: {exc}")

    goal = mem_data.get("goal", "Unknown goal")

    # Calculate working days
    working_set = _working_day_set(plan.schedule_prefs)
    suggested_days = milestone.suggested_days or 14
    start_date = date.today()
    working_days_count = _count_working_days(start_date, suggested_days, working_set)

    if working_days_count < 1:
        working_days_count = 1  # at least one task

    # Extract daily time commitment
    daily_minutes = 30
    if plan.schedule_prefs and isinstance(plan.schedule_prefs, dict):
        daily_minutes = plan.schedule_prefs.get("daily_minutes", 30)

    # Build prompt
    prompt = TASK_PROMPT.format(
        goal=goal,
        milestone_title=milestone.title,
        milestone_description=milestone.description or "",
        milestone_outcome=milestone.outcome or "",
        working_days_count=working_days_count,
        daily_minutes=daily_minutes,
        start_date=start_date.isoformat(),
    )

    # Call LLM
    parsed = await asyncio.to_thread(_parse_json_with_retry, prompt)

    # Validate response
    tasks_data = parsed.get("tasks", [])
    if not tasks_data or not isinstance(tasks_data, list):
        raise PlanGenerationError(
            "LLM returned no tasks array",
            raw_response=json.dumps(parsed),
        )

    # Create TaskRow records
    created: list[TaskRow] = []
    for t in tasks_data:
        day_offset = t.get("day_offset", 0)
        scheduled_date = _date_for_day_offset(start_date, day_offset, working_set)

        row_data = {
            "plan_id": str(plan.id),
            "milestone_id": str(mid),
            "title": t.get("title", "Untitled task"),
            "description": t.get("description", ""),
            "due_date": scheduled_date.isoformat(),
            "duration_minutes": t.get("duration_minutes", 30),
            "order_index": t.get("order_index", 0),
            "status": "pending",
            "priority": "medium",
            "difficulty": "intermediate",
        }

        res = db.client.table("tasks").insert(row_data).execute()
        if res and res[1]:
            created.append(db._map_task(res[1][0]))

    # Invalidate milestone insight cache since tasks changed
    try:
        db.clear_milestone_insight_json(mid)
    except Exception:
        pass

    return created
