"""Real-time event triggers — proactive nudges based on user behavior.

Checks run after task events and return optional nudge dicts that the
router can forward to the app as push-like messages.

Triggers:
1. Completion streak  → encouragement nudge
2. Inactivity (2+ days) → gentle reminder
3. Repeated skips (same task 3x) → suggest permanent skip
4. Deadline risk       → urgency nudge
5. Failure threshold  → trigger deep review
"""

from __future__ import annotations

import logging
from datetime import date, timedelta
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import EventType, TaskStatus

logger = logging.getLogger(__name__)


def check_completion_streak(user_id: UUID) -> dict | None:
    """If user completed all tasks 3+ days in a row, send encouragement."""
    streak = 0
    for days_ago in range(7):
        d = date.today() - timedelta(days=days_ago + 1)
        tasks = adaptive_store.get_tasks_for_date(user_id, d)
        if not tasks:
            break
        total = len(tasks)
        done = sum(1 for t in tasks if t.status == TaskStatus.done)
        if total > 0 and done == total:
            streak += 1
        else:
            break

    if streak >= 3:
        return {
            "type": "nudge",
            "trigger": "completion_streak",
            "message": f"Amazing! You've completed all tasks for {streak} days in a row. Keep it up!",
            "streak": streak,
        }
    return None


def check_inactivity(user_id: UUID) -> dict | None:
    """If user has had no completed tasks for 2+ days, send a gentle reminder."""
    inactive_days = 0
    for days_ago in range(5):
        d = date.today() - timedelta(days=days_ago + 1)
        tasks = adaptive_store.get_tasks_for_date(user_id, d)
        if not tasks:
            inactive_days += 1
            continue
        done = sum(1 for t in tasks if t.status == TaskStatus.done)
        if done == 0:
            inactive_days += 1
        else:
            break

    if inactive_days >= 2:
        return {
            "type": "nudge",
            "trigger": "inactivity",
            "message": "You haven't completed any tasks in a couple of days. Even one small task counts — want me to suggest something light?",
            "inactive_days": inactive_days,
        }
    return None


def check_repeated_skips(user_id: UUID, task_id: UUID) -> dict | None:
    """If the same task has been skipped/rescheduled 3+ times, suggest permanent skip."""
    task = adaptive_store.get_task(task_id)
    if task is None:
        return None

    if task.carry_over_count >= 3:
        return {
            "type": "suggestion",
            "trigger": "repeated_skips",
            "message": f"'{task.title}' has been rescheduled {task.carry_over_count} times. Consider skipping it permanently or breaking it into smaller steps.",
            "task_id": str(task.id),
            "carry_over_count": task.carry_over_count,
        }
    return None


def check_deadline_risk_nudge(user_id: UUID) -> dict | None:
    """If any plan has deadline risk, send an urgency nudge."""
    from backend.adaptive.services.adaptation_rules import check_deadline_risk

    risks = check_deadline_risk(user_id, date.today())
    if risks:
        top_risk = risks[0]
        return {
            "type": "warning",
            "trigger": "deadline_risk",
            "message": f"Plan '{top_risk['plan_title']}' is falling behind — you need {top_risk['required_pace']} tasks/day but are doing {top_risk['actual_pace']}/day. Only {top_risk['days_remaining']} days left.",
            "plan_id": top_risk["plan_id"],
        }
    return None


def run_all_triggers(user_id: UUID, task_id: UUID | None = None) -> list[dict]:
    """Run all applicable triggers and return a list of nudge dicts."""
    nudges: list[dict] = []

    # Always-run triggers
    result = check_completion_streak(user_id)
    if result:
        nudges.append(result)

    result = check_inactivity(user_id)
    if result:
        nudges.append(result)

    result = check_deadline_risk_nudge(user_id)
    if result:
        nudges.append(result)

    # Task-specific triggers
    if task_id:
        result = check_repeated_skips(user_id, task_id)
        if result:
            nudges.append(result)

    return nudges


def check_failure_threshold(user_id: UUID) -> dict | None:
    """Check if the user has hit a failure threshold and needs a deep review.

    This is a trigger that signals the system should run a deep review,
    but the actual deep review is triggered separately by task_observer.
    This function returns a nudge to inform the user.
    """
    from backend.adaptive.services.deep_review import deep_review_service

    if deep_review_service._check_failure_threshold(user_id):
        return {
            "type": "warning",
            "trigger": "failure_threshold",
            "message": "It looks like you've been struggling with tasks recently. I'll review your plans and suggest adjustments.",
        }
    return None
