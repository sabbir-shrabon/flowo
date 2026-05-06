"""Milestone Generator — creates milestones from plan memory via LLM."""

from __future__ import annotations

import asyncio
import json
from uuid import UUID

from backend.adaptive.db import AdaptiveStore
from backend.adaptive.models import MilestoneRow, MilestoneStatus, PlanStatus
from backend.lib.llm import chatResponse


MILESTONE_PROMPT = """You are a planning expert. Create a milestone-based roadmap.
Return ONLY valid JSON, no explanation.

Create milestones for this goal:
Goal: {goal}
Summary: {summary}
Keywords: {keywords}
Current level: {current_level}
Total duration: {duration_days} days
Work schedule: {schedule_type}
Daily time commitment: {daily_minutes} minutes per day

Return this JSON structure:
{{
  "milestones": [
    {{
      "title": "short milestone name",
      "description": "2-3 sentences on what this milestone covers",
      "order_index": 0,
      "suggested_days": 14,
      "outcome": "what the user can do after completing this milestone"
    }}
  ]
}}

Rules:
- Create between 3 and 6 milestones depending on total duration
- suggested_days for all milestones must sum to exactly {duration_days}
- First milestone must be achievable and confidence-building
- Last milestone is the final goal achieved
- Each milestone must have a clear, measurable outcome
- With {daily_minutes} min/day, keep milestones realistic — less daily time means more days per milestone
- Return ONLY valid JSON."""

RETRY_PROMPT = """You previously failed to return valid JSON. You MUST return ONLY a raw JSON object — no markdown fences, no explanation, no extra text. Just the JSON. Try again:

{previous_response}

Return the corrected JSON now."""


class PlanGenerationError(Exception):
    """Raised when milestone generation fails after retry."""
    def __init__(self, message: str, raw_response: str | None = None):
        super().__init__(message)
        self.raw_response = raw_response


def _call_llm(prompt: str) -> str:
    """Synchronous LLM call wrapper."""
    return chatResponse(prompt)


def _clean_llm_response(raw: str) -> str:
    """Strip markdown fences and whitespace from LLM output."""
    content = raw.strip()
    if content.startswith("```json"):
        content = content[7:]
    elif content.startswith("```"):
        content = content[3:]
    if content.endswith("```"):
        content = content[:-3]
    return content.strip()


def _parse_json_with_retry(raw_prompt: str) -> dict:
    """Call LLM, parse JSON, retry once on failure. Returns parsed dict or raises PlanGenerationError."""
    raw = _call_llm(raw_prompt)
    cleaned = _clean_llm_response(raw)

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    # Retry once with stricter prompt
    retry_prompt = RETRY_PROMPT.format(previous_response=cleaned)
    raw = _call_llm(retry_prompt)
    cleaned = _clean_llm_response(raw)

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise PlanGenerationError(
            f"Milestone generation failed after retry: {exc}",
            raw_response=cleaned,
        )


async def generate(
    plan_id: str,
    user_id: str,
    db: AdaptiveStore,
) -> list[MilestoneRow]:
    """
    Generate milestones for a plan from its linked memory record.

    1. Fetch plan (has goal_id, duration_days, schedule_prefs)
    2. Fetch memory by goal_id → parse JSON content
    3. Build prompt and call LLM
    4. Parse response and create MilestoneRow records
    5. Set first milestone active, rest locked
    6. Update plan status from 'setup' to 'active'
    7. Return list of MilestoneRow
    """
    pid = UUID(plan_id) if isinstance(plan_id, str) else plan_id
    uid = UUID(user_id) if isinstance(user_id, str) else user_id

    # Fetch plan
    plan = db.get_plan(pid)
    if plan is None:
        raise PlanGenerationError(f"Plan {plan_id} not found")

    # Resolve memory ID: prefer plan.memory_id, fall back to plan.goal_id for legacy plans
    mem_id = plan.memory_id or plan.goal_id
    if mem_id is None:
        raise PlanGenerationError(f"Plan {plan_id} has no linked memory (memory_id and goal_id are both None)")

    if plan.duration_days is None:
        raise PlanGenerationError(f"Plan {plan_id} has no duration_days set")

    # Fetch memory record
    memory = db.get_memory(mem_id)
    if memory is None:
        raise PlanGenerationError(f"Memory record {mem_id} not found")

    # Parse memory JSON
    try:
        mem_data = json.loads(memory.value)
    except (json.JSONDecodeError, TypeError) as exc:
        raise PlanGenerationError(f"Failed to parse memory JSON: {exc}")

    goal = mem_data.get("goal", "Unknown goal")
    summary = mem_data.get("summary", "")
    keywords = mem_data.get("keywords", [])
    keywords_str = ", ".join(keywords) if isinstance(keywords, list) else str(keywords)
    current_level = mem_data.get("current_level", "beginner")

    schedule_type = "unspecified"
    daily_minutes = 30
    if plan.schedule_prefs and isinstance(plan.schedule_prefs, dict):
        schedule_type = plan.schedule_prefs.get("type", "unspecified")
        daily_minutes = plan.schedule_prefs.get("daily_minutes", 30)

    # Build prompt
    prompt = MILESTONE_PROMPT.format(
        goal=goal,
        summary=summary,
        keywords=keywords_str,
        current_level=current_level,
        duration_days=plan.duration_days,
        schedule_type=schedule_type,
        daily_minutes=daily_minutes,
    )

    # Call LLM (async wrapper around sync call)
    parsed = await asyncio.to_thread(_parse_json_with_retry, prompt)

    # Validate response structure
    milestones_data = parsed.get("milestones", [])
    if not milestones_data or not isinstance(milestones_data, list):
        raise PlanGenerationError(
            "LLM returned no milestones array",
            raw_response=json.dumps(parsed),
        )

    # Create milestone records
    created: list[MilestoneRow] = []
    for idx, ms in enumerate(milestones_data):
        ms_status = MilestoneStatus.active
        milestone = db.create_milestone(
            user_id=uid,
            plan_id=pid,
            data={
                "title": ms.get("title", f"Milestone {idx + 1}"),
                "description": ms.get("description", ""),
                "order_index": ms.get("order_index", idx),
                "status": ms_status,
                "suggested_days": ms.get("suggested_days"),
                "outcome": ms.get("outcome"),
            },
        )
        created.append(milestone)

    # Update plan status from setup → active
    db.update_plan(pid, status=PlanStatus.active)

    return created
