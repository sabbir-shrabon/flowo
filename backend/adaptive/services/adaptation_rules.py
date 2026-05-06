"""Adaptation rules — pure rule functions callable on-demand.

Each rule is an independent function that can be triggered by the
adaptation engine in real-time, not just at end-of-day.

Rules:
1. audit_today()              — categorize tasks
2. reschedule_pending()       — move pending tasks to next working day
3. check_overload()           — spread overflow when a day exceeds limits
4. flag_struggling_task()     — mark a single task as struggling
5. detect_consecutive_misses()— detect 3-day miss streaks (burn-out)
6. check_deadline_risk()      — flag plans falling behind pace
7. generate_daily_summary()   — LLM summary (communication only)
"""

from __future__ import annotations

import logging
from datetime import date, timedelta
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import EventType, TaskRow, TaskStatus
from backend.lib.llm import chatResponse

logger = logging.getLogger(__name__)


# ── Helpers ────────────────────────────────────────────────────────────────────

def get_next_working_day(from_date: date, working_days: list[int] | None = None) -> date:
    if working_days is None:
        working_days = [0, 1, 2, 3, 4]
    candidate = from_date + timedelta(days=1)
    while candidate.weekday() not in working_days:
        candidate += timedelta(days=1)
    return candidate


# ── Rule Functions ─────────────────────────────────────────────────────────────

def audit_today(user_id: UUID, today: date) -> dict:
    all_tasks = adaptive_store.get_tasks_for_date(user_id, today)
    completed = [t for t in all_tasks if t.status == TaskStatus.done]
    skipped = [t for t in all_tasks if t.status == TaskStatus.skipped]
    partial = [t for t in all_tasks if t.status == TaskStatus.partial]
    missed = [t for t in all_tasks if t.status == TaskStatus.pending]
    return {
        "completed": completed, "skipped": skipped, "partial": partial, "missed": missed,
        "all": all_tasks,
        "counts": {"completed": len(completed), "skipped": len(skipped), "partial": len(partial), "missed": len(missed), "total": len(all_tasks)},
    }


def reschedule_pending(user_id: UUID, today: date, audit: dict) -> list[TaskRow]:
    """No-op: overdue tasks are now handled by virtual rollover in the scheduler.

    The scheduler keeps unfinished tasks visible on the Today screen without
    physically rescheduling them in the database. This avoids midnight processing
    and ensures the user always sees their pending work."""
    return []


def check_overload(user_id: UUID, target_date: date) -> list[TaskRow]:
    """No-op: overload spreading is now handled by the adaptive scheduler."""
    return []



def flag_struggling_task(user_id: UUID, task_id: UUID) -> None:
    adaptive_store.set_task_struggling(task_id, struggling=True)
    try:
        task = adaptive_store.get_task(task_id)
        if task:
            adaptive_store.create_episodic_memory(
                user_id=user_id, type="pattern",
                content=f"Task '{task.title}' rescheduled {task.carry_over_count}x — struggling",
                context_json={"task_id": str(task.id), "plan_id": str(task.plan_id), "carry_over_count": task.carry_over_count},
                learned_rule="struggling_task_detected",
            )
    except Exception as e:
        logger.warning("Failed episodic memory for struggling task: %s", e)



def detect_consecutive_misses(user_id: UUID, today: date) -> dict | None:
    """No-op: miss detection/auto-reduce is now handled by the adaptive scheduler."""
    return None


def check_deadline_risk(user_id: UUID, today: date) -> list[dict]:
    active_plans = adaptive_store.list_active_plans(user_id)
    at_risk: list[dict] = []
    for plan in active_plans:
        if not plan.duration_days or plan.duration_days <= 0:
            continue
        # Use explicit start_date from schedule_prefs if available
        prefs = plan.schedule_prefs or {}
        start_raw = prefs.get("start_date")
        if isinstance(start_raw, str):
            try:
                start_date = date.fromisoformat(start_raw)
            except ValueError:
                plan_date = plan.created_at
                if plan_date.tzinfo is not None:
                    plan_date = plan_date.replace(tzinfo=None)
                start_date = date(plan_date.year, plan_date.month, plan_date.day)
        else:
            plan_date = plan.created_at
            if plan_date.tzinfo is not None:
                plan_date = plan_date.replace(tzinfo=None)
            start_date = date(plan_date.year, plan_date.month, plan_date.day)
        # Use explicit end_date from schedule_prefs if available
        end_raw = prefs.get("end_date")
        if isinstance(end_raw, str):
            try:
                deadline = date.fromisoformat(end_raw)
            except ValueError:
                deadline = start_date + timedelta(days=plan.duration_days)
        else:
            deadline = start_date + timedelta(days=plan.duration_days)
        days_elapsed = max(1, (today - start_date).days)
        days_remaining = max(1, (deadline - today).days)
        res = adaptive_store.client.table("tasks").select("status").eq("plan_id", str(plan.id)).execute()
        if not res or not res[1]:
            continue
        total = len(res[1])
        done = sum(1 for r in res[1] if r.get("status") == "done")
        if total == 0:
            continue
        required_pace = (total - done) / days_remaining
        actual_pace = done / days_elapsed
        if actual_pace > 0 and required_pace > actual_pace * 1.3:
            at_risk.append({
                "plan_id": str(plan.id), "plan_title": plan.title,
                "required_pace": round(required_pace, 2), "actual_pace": round(actual_pace, 2),
                "days_remaining": days_remaining, "tasks_remaining": total - done,
            })
    return at_risk


# ── LLM Summary (communication only) ────────────────────────────────────────

_SUMMARY_PROMPT = """You are an adaptive planning assistant writing a brief daily summary.

Today's stats:
- Completed: {completed} tasks
- Missed (still pending): {missed} tasks
- Skipped: {skipped} tasks
- Partially done: {partial} tasks
- Rescheduled to future: {rescheduled} tasks
{extra_context}

Write a 1-2 sentence summary of how today went and what's coming next. Be encouraging but honest. Do NOT suggest scheduling changes — those are already handled by the system."""


def generate_daily_summary(user_id: UUID, audit: dict, extra_lines: list[str]) -> str:
    stats = audit.get("counts", audit)
    extra = "\n".join(extra_lines) if extra_lines else ""
    prompt = _SUMMARY_PROMPT.format(
        completed=stats.get("completed", 0), missed=stats.get("missed", 0),
        skipped=stats.get("skipped", 0), partial=stats.get("partial", 0),
        rescheduled=stats.get("rescheduled", 0), extra_context=extra,
    )
    try:
        return chatResponse(prompt).strip()
    except Exception as e:
        logger.warning("Summary LLM failed: %s", e)
        return ""
