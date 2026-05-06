"""Adaptation Engine — real-time, event-driven adaptation.

Replaces the old batch model. Adapts the moment a relevant event occurs.
Deep review is now trigger-based (see deep_review.py), not cron-based.
"""

from __future__ import annotations

import logging
from datetime import date
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import EventType, TaskStatus
from backend.adaptive.services.adaptation_rules import (
    check_overload, flag_struggling_task, get_next_working_day,
)

logger = logging.getLogger(__name__)


def adapt_on_event(user_id: UUID, event_type: str, context: dict) -> dict:
    """Central adaptation entry point. Called by task_observer on any event."""
    result = {"event_type": event_type, "adapted": False, "actions": []}
    try:
        handlers = {
            "task_status_changed": _handle_status_change,
            "task_skipped": _handle_skip,
            "due_date_passed": _handle_due_date_passed,
            "user_busy": _handle_busy,
            "workload_exceeded": _handle_workload_exceeded,
        }
        handler = handlers.get(event_type)
        if handler:
            actions = handler(user_id, context)
            result["adapted"] = bool(actions)
            result["actions"] = actions
        else:
            logger.warning("Unknown adaptation event: %s", event_type)
    except Exception as e:
        logger.error("Adaptation engine failed for %s: %s", event_type, e)
        result["error"] = str(e)
    return result


def _handle_status_change(user_id: UUID, context: dict) -> list[dict]:
    actions: list[dict] = []
    new_status = context.get("new_status", "")
    task_id_str = context.get("task_id")

    if new_status in ("done", "skipped"):
        actions.extend(_recalculate_workload(user_id))
    elif new_status == "partial":
        if task_id_str:
            try:
                task = adaptive_store.get_task(UUID(task_id_str))
                if task and task.carry_over_count >= 2 and not task.struggling:
                    flag_struggling_task(user_id, UUID(task_id_str))
                    actions.append({"action": "flag_struggling", "task_id": task_id_str})
            except Exception as e:
                logger.warning("Failed struggling check on partial: %s", e)
        actions.extend(_recalculate_workload(user_id))
    return actions


def _handle_skip(user_id: UUID, context: dict) -> list[dict]:
    actions: list[dict] = []
    task_id_str = context.get("task_id")
    if task_id_str:
        try:
            task = adaptive_store.get_task(UUID(task_id_str))
            if task and task.carry_over_count >= 2 and not task.struggling:
                flag_struggling_task(user_id, UUID(task_id_str))
                actions.append({"action": "flag_struggling", "task_id": task_id_str})
        except Exception as e:
            logger.warning("Failed struggling check on skip: %s", e)
    actions.extend(_recalculate_workload(user_id))
    overload_moves = check_overload(user_id, get_next_working_day(date.today()))
    if overload_moves:
        actions.append({"action": "overload_spread", "moved": len(overload_moves)})
    return actions


def _handle_due_date_passed(user_id: UUID, context: dict) -> list[dict]:
    """No-op: overdue tasks are now handled by virtual rollover in the scheduler.

    The scheduler keeps unfinished tasks visible on the Today screen without
    physically rescheduling them in the database. This avoids midnight processing
    and ensures the user always sees their pending work."""
    return []


def _handle_busy(user_id: UUID, _context: dict) -> list[dict]:
    from backend.adaptive.services.adjuster import adjuster_service
    rescheduled = adjuster_service.handle_busy(user_id)
    return [{"action": "busy_day_reschedule", "rescheduled_count": len(rescheduled)}]


def _handle_workload_exceeded(user_id: UUID, _context: dict) -> list[dict]:
    overload_moves = check_overload(user_id, date.today())
    return [{"action": "overload_spread", "moved": len(overload_moves)}]


def _recalculate_workload(user_id: UUID) -> list[dict]:
    """No-op: workload is now handled by the adaptive scheduler (round(undone/remaining_working_days))."""
    return []
