"""Rule-based automatic adjustment logic — no LLM."""

from __future__ import annotations

import logging
from datetime import date, timedelta
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import EventType, TaskRow, TaskStatus

logger = logging.getLogger(__name__)


class AdjusterService:
    """Pure rule-based adjustments. Every action also records an event."""

    # ── 1. Task skipped → move to next day + increase carry_over ────────────

    def handle_skip(self, user_id: UUID, task_id: UUID) -> TaskRow | None:
        """
        When a task is skipped:
        - increment carry_over_count
        - move due_date to tomorrow
        - reset status to pending
        - record a 'rescheduled' event
        """
        task = adaptive_store.get_task(task_id)
        if task is None:
            return None

        # Increment carry-over
        adaptive_store.increment_carry_over(task_id)

        # Move to next day + reset status
        tomorrow = date.today() + timedelta(days=1)
        updated = adaptive_store.reschedule_task(task_id, tomorrow)

        # Record rescheduled event
        if updated:
            adaptive_store.record_event(
                user_id=user_id,
                task_id=task_id,
                plan_id=task.plan_id,
                event_type=EventType.rescheduled,
                feedback_text="auto-rescheduled after skip",
            )

            # Check if carry_over now exceeds threshold → reduce difficulty
            refreshed = adaptive_store.get_task(task_id)
            if refreshed and refreshed.carry_over_count > 2:
                self.reduce_difficulty(user_id, task_id)

        return adaptive_store.get_task(task_id)

    # ── 2. carry_over_count > 2 → reduce difficulty ─────────────────────────

    def reduce_difficulty(self, user_id: UUID, task_id: UUID) -> TaskRow | None:
        """
        Step difficulty down one level: hard → intermediate → easy.
        If already easy, no change. Records a 'rescheduled' event with reason.
        """
        task = adaptive_store.get_task(task_id)
        if task is None:
            return None

        updated = adaptive_store.reduce_task_difficulty(task_id)
        if updated and updated.difficulty != task.difficulty:
            adaptive_store.record_event(
                user_id=user_id,
                task_id=task_id,
                plan_id=task.plan_id,
                event_type=EventType.rescheduled,
                feedback_text=f"difficulty reduced: {task.difficulty.value} → {updated.difficulty.value} (carry_over={updated.carry_over_count})",
            )
        return updated

    # ── 3. "I'm busy" → keep 1 task per plan, reschedule the rest ────────────

    def handle_busy(self, user_id: UUID) -> list[TaskRow]:
        """
        User says they're busy — keep 1 task per active plan (lowest order_index),
        reschedule all other pending/partial tasks to next working day,
        then run overload check on the target day.
        """
        from backend.adaptive.services.adaptation_rules import get_next_working_day, check_overload

        today = date.today()
        due_tasks = adaptive_store.get_due_tasks(user_id, today)

        # Group by plan
        by_plan: dict[UUID, list[TaskRow]] = {}
        for t in due_tasks:
            by_plan.setdefault(t.plan_id, []).append(t)

        # For each plan, keep 1 task (lowest order_index), reschedule the rest
        kept_ids: set[UUID] = set()
        to_reschedule: list[TaskRow] = []

        for plan_id, tasks in by_plan.items():
            tasks.sort(key=lambda t: t.order_index)
            kept_ids.add(tasks[0].id)  # keep the first task
            to_reschedule.extend(tasks[1:])

        # If a plan has no due tasks today, skip it (nothing to keep)
        rescheduled: list[TaskRow] = []
        for task in to_reschedule:
            plan = adaptive_store.get_plan(task.plan_id)
            working_days = None
            if plan and plan.schedule_prefs:
                working_days = plan.schedule_prefs.get("working_days")
            next_day = get_next_working_day(today, working_days)

            try:
                updated = adaptive_store.set_task_rescheduled(task.id, next_day, today)
            except Exception:
                updated = adaptive_store.reschedule_task(task.id, next_day)

            adaptive_store.record_event(
                user_id=user_id,
                task_id=task.id,
                plan_id=task.plan_id,
                event_type=EventType.rescheduled,
                feedback_text="rescheduled due to busy day",
            )
            if updated:
                rescheduled.append(updated)

        # Run overload check on the next working day
        if rescheduled:
            try:
                next_day = get_next_working_day(today)
                check_overload(user_id, next_day)
            except Exception as e:
                logger.warning("Overload check after busy day failed: %s", e)

        # Create episodic memory for busy day
        try:
            adaptive_store.create_episodic_memory(
                user_id=user_id,
                type="episode",
                content=f"User marked busy day — kept {len(kept_ids)} tasks, rescheduled {len(rescheduled)} to next working day",
                context_json={"kept": len(kept_ids), "rescheduled": len(rescheduled)},
            )
        except Exception:
            pass

        return rescheduled

    def reschedule_overflow(self, user_id: UUID) -> list[TaskRow]:
        """No-op: overflow is now handled by the adaptive scheduler."""
        return []

    # ── 5. User wants more → pull next task from plan ───────────────────────

    def pull_next_task(self, user_id: UUID, plan_id: UUID | None = None) -> TaskRow | None:
        """
        Pull the next pending task from a plan and set its due_date to today.
        If no plan_id given, picks from the highest-priority active plan
        that has pending tasks beyond today.
        """
        today = date.today()

        if plan_id is None:
            # Find highest-priority plan with upcoming tasks
            active_plans = adaptive_store.list_active_plans(user_id)
            active_plans.sort(key=lambda p: {"high": 0, "medium": 1, "low": 2}.get(p.priority.value, 1))
            for plan in active_plans:
                next_task = adaptive_store.get_next_pending_task(plan.id, after_date=today)
                if next_task:
                    plan_id = plan.id
                    break
            if plan_id is None:
                return None

        next_task = adaptive_store.get_next_pending_task(plan_id, after_date=today)
        if next_task is None:
            return None

        updated = adaptive_store.reschedule_task(next_task.id, today)
        if updated:
            adaptive_store.record_event(
                user_id=user_id,
                task_id=next_task.id,
                plan_id=plan_id,
                event_type=EventType.rescheduled,
                feedback_text="pulled forward by user request",
            )
        return updated


adjuster_service = AdjusterService()
