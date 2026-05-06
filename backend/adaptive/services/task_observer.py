"""Task Observer — real-time event-driven adaptation trigger.

Watches for state changes and immediately triggers the adaptation engine:
- Task status changed (done, skipped, partial)
- Task due_date passed (checked on app open or periodic poll)
- User marked busy
- User skipped a task

Also triggers deep review on failure thresholds (consecutive bad days).
"""

from __future__ import annotations

import logging
from datetime import date
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import TaskStatus

logger = logging.getLogger(__name__)


def on_task_status_changed(user_id: UUID, task_id: UUID, new_status: TaskStatus) -> dict:
    """Called whenever a task's status changes.

    Triggers immediate adaptation based on the new status:
    - done    → check milestone completion, recalculate remaining workload
    - skipped → recalculate workload for rest of day
    - partial → flag struggling if repeated, recalculate workload
    """
    from backend.adaptive.services.adaptation_engine import adapt_on_event

    task = adaptive_store.get_task(task_id)
    if task is None:
        return {"adapted": False, "reason": "task not found"}

    result = adapt_on_event(user_id, event_type="task_status_changed", context={
        "task_id": task_id,
        "plan_id": task.plan_id,
        "new_status": new_status.value,
        "old_status": None,  # we don't have the old status here
        "carry_over_count": task.carry_over_count,
    })

    # Check if failure threshold reached → trigger deep review
    if new_status in (TaskStatus.skipped, TaskStatus.partial):
        try:
            from backend.adaptive.services.deep_review import deep_review_service
            deep_review_service.check_and_trigger(user_id)
        except Exception as e:
            logger.warning("Deep review failure check failed: %s", e)

    return result


def on_task_skipped(user_id: UUID, task_id: UUID, skip_type: str = "skip_today") -> dict:
    """Called when a user skips a task.

    Immediately recalculates the workload for the rest of the day
    and checks if overload spreading is needed.
    """
    from backend.adaptive.services.adaptation_engine import adapt_on_event

    task = adaptive_store.get_task(task_id)
    if task is None:
        return {"adapted": False, "reason": "task not found"}

    result = adapt_on_event(user_id, event_type="task_skipped", context={
        "task_id": task_id,
        "plan_id": task.plan_id,
        "skip_type": skip_type,
        "carry_over_count": task.carry_over_count,
    })

    # Check if failure threshold reached → trigger deep review
    try:
        from backend.adaptive.services.deep_review import deep_review_service
        deep_review_service.check_and_trigger(user_id)
    except Exception as e:
        logger.warning("Deep review failure check failed: %s", e)

    return result


def on_due_date_passed(user_id: UUID, task_id: UUID) -> dict:
    """Called when a task's due_date has passed and it's still pending.

    This is the real-time equivalent of the old "reschedule pending" rule.
    Instead of waiting for midnight, we adapt immediately.
    """
    from backend.adaptive.services.adaptation_engine import adapt_on_event

    task = adaptive_store.get_task(task_id)
    if task is None:
        return {"adapted": False, "reason": "task not found"}

    if task.status != TaskStatus.pending:
        return {"adapted": False, "reason": f"task status is {task.status.value}, not pending"}

    result = adapt_on_event(user_id, event_type="due_date_passed", context={
        "task_id": task_id,
        "plan_id": task.plan_id,
        "due_date": task.due_date.isoformat() if task.due_date else None,
        "carry_over_count": task.carry_over_count,
    })

    return result


def on_user_busy(user_id: UUID) -> dict:
    """Called when user marks themselves as busy.

    Triggers the smart busy-day logic: keep 1 task per plan, reschedule rest.
    """
    from backend.adaptive.services.adaptation_engine import adapt_on_event

    result = adapt_on_event(user_id, event_type="user_busy", context={})
    return result


def check_overdue_tasks(user_id: UUID) -> list[dict]:
    """No-op: overdue tasks are now handled by virtual rollover in the scheduler.

    The scheduler keeps unfinished tasks visible on the Today screen without
    physically rescheduling them. No midnight processing or catch-up needed."""
    return []


def on_app_open(user_id: UUID) -> dict:
    """Called when the user opens the app.

    Performs catch-up adaptation:
    1. Check for overdue tasks and adapt them
    2. Check if today's workload needs rebalancing
    3. Run proactive triggers (inactivity, deadline risk, streaks)
    """
    from backend.adaptive.services.adaptation_engine import adapt_on_event
    from backend.adaptive.services.event_triggers import run_all_triggers

    # 1. Overdue tasks are handled by virtual rollover in the scheduler
    # (no physical rescheduling needed)

    # 2. Rebalance today if needed
    today = date.today()
    today_tasks = adaptive_store.get_tasks_for_date(user_id, today)
    rebalance_result = None

    # 3. Run proactive triggers
    nudges = run_all_triggers(user_id)

    # 4. Generate a brief daily summary if one doesn't exist yet today
    summary = None
    existing = adaptive_store.get_daily_summary(user_id, today)
    if not existing and today_tasks:
        from backend.adaptive.services.adaptation_rules import generate_daily_summary
        audit = {
            "counts": {
                "completed": sum(1 for t in today_tasks if t.status == TaskStatus.done),
                "missed": sum(1 for t in today_tasks if t.status == TaskStatus.pending),
                "skipped": sum(1 for t in today_tasks if t.status == TaskStatus.skipped),
                "partial": sum(1 for t in today_tasks if t.status == TaskStatus.partial),
                "total": len(today_tasks),
            },
        }
        summary = generate_daily_summary(user_id, audit, [])

    return {
        "overdue_adapted": 0,
        "rebalance": rebalance_result,
        "nudges": nudges,
        "summary": summary,
    }
