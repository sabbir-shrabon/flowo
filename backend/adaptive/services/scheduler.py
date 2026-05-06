"""Scheduler - selects today's tasks in roadmap order.

Core concepts:
  - Working day number: 1st, 2nd, 3rd... working day relative to plan start date.
  - Virtual rollover: unfinished overdue tasks stay visible without midnight DB writes.
  - Bounded daily view: rollover is capped by the plan's current work pace so Today
    does not grow forever.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from math import ceil
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import PlanPriority, PlanRow, PlanStatus, TaskRow, TaskStatus


_PRIORITY_ORDER = {
    PlanPriority.high: 0,
    PlanPriority.medium: 1,
    PlanPriority.low: 2,
}


def _plan_sort_key(plan: PlanRow):
    created = plan.created_at
    if created.tzinfo is not None:
        created = created.replace(tzinfo=None)
    return (_PRIORITY_ORDER.get(plan.priority, 1), created)


def _plan_start_date(plan: PlanRow) -> date:
    """Use an explicit schedule start if present, otherwise the plan creation day."""
    prefs = plan.schedule_prefs or {}
    start = prefs.get("start_date") or prefs.get("adapt_start_date")
    if isinstance(start, str):
        try:
            return date.fromisoformat(start)
        except ValueError:
            pass
    created = plan.created_at
    if created.tzinfo is not None:
        created = created.replace(tzinfo=None)
    return date(created.year, created.month, created.day)


def _plan_end_date(plan: PlanRow) -> date | None:
    """Return the explicit end_date from schedule_prefs if present."""
    prefs = plan.schedule_prefs or {}
    end = prefs.get("end_date")
    if isinstance(end, str):
        try:
            return date.fromisoformat(end)
        except ValueError:
            pass
    return None


def _plan_deadline(plan: PlanRow) -> date:
    """Return the inclusive calendar deadline for a plan."""
    start = _plan_start_date(plan)
    duration = max(1, plan.duration_days or 1)
    return _plan_end_date(plan) or (start + timedelta(days=duration - 1))


def _get_working_days(plan: PlanRow) -> list[int]:
    """Get working days from schedule_prefs, fallback to Mon-Fri."""
    prefs = plan.schedule_prefs or {}
    wd = prefs.get("working_days", [])
    return wd if wd else list(range(5))


def _current_working_day(plan: PlanRow, on_date: date) -> int:
    """Calculate which working day it is, 1-indexed, relative to plan start.

    Returns 0 if on_date is before the plan start date.
    """
    start = _plan_start_date(plan)
    if on_date < start:
        return 0
    working_days = _get_working_days(plan)
    count = 0
    current = start
    while current <= on_date:
        if current.weekday() in working_days:
            count += 1
        current += timedelta(days=1)
    return count


def _remaining_working_days(plan: PlanRow, on_date: date) -> int:
    """Count working days from on_date/start through the inclusive deadline."""
    working_days = _get_working_days(plan)
    start = _plan_start_date(plan)
    deadline = _plan_deadline(plan)

    if on_date > deadline:
        return 0

    count = 0
    current = max(on_date, start)
    while current <= deadline:
        if current.weekday() in working_days:
            count += 1
        current += timedelta(days=1)
    return max(count, 1)


class SchedulerService:
    """Selects daily tasks as a locked per-day batch."""

    def get_today_tasks(self, user_id: UUID, on_date: date | None = None) -> dict:
        """
        Daily quota lock:
        1. If a batch already exists for this user/date, return those exact tasks.
        2. Otherwise calculate the quota once, store the selected task IDs, and
           reuse that batch for the rest of the day.
        """
        if on_date is None:
            on_date = date.today()

        locked_batch = adaptive_store.get_daily_task_batch(user_id, on_date)
        if locked_batch is not None:
            return self._result_from_batch(user_id, on_date, locked_batch)

        result = self._calculate_daily_batch(user_id, on_date)
        adaptive_store.create_daily_task_batch(
            user_id=user_id,
            on_date=on_date,
            daily_limit=result["daily_limit"],
            task_ids=[task.id for task in result["tasks"]],
            metadata={
                "plans_working_day": result["plans_working_day"],
                "plans_queried": result["plans_queried"],
            },
        )
        return result

    def _calculate_daily_batch(self, user_id: UUID, on_date: date) -> dict:
        active_plans = [
            p for p in adaptive_store.list_active_plans(user_id)
            if p.status == PlanStatus.active
        ]
        active_plans.sort(key=_plan_sort_key)

        selected_by_plan: list[tuple[PlanRow, list[TaskRow], int, int]] = []
        total_available = 0
        largest_plan_slice = 0

        plans_working_day: dict[str, int] = {}

        for plan in active_plans:
            if not (plan.schedule_prefs or {}).get("working_days"):
                continue

            working_days = _get_working_days(plan)
            working_day_num = _current_working_day(plan, on_date)
            plans_working_day[str(plan.id)] = working_day_num
            if working_day_num <= 0:
                continue

            ordered_tasks = self._ordered_tasks_for_plan(user_id, plan)
            if not ordered_tasks:
                continue

            remaining_undone = [
                t for t in ordered_tasks
                if t.status in (TaskStatus.pending, TaskStatus.partial)
            ]
            if not remaining_undone:
                tasks_per_day = 0
            else:
                remaining_days = _remaining_working_days(plan, on_date)
                tasks_per_day = max(1, ceil(len(remaining_undone) / remaining_days))
                largest_plan_slice = max(largest_plan_slice, tasks_per_day)

            is_working_today = on_date.weekday() in working_days
            rollover: list[TaskRow] = []
            fresh: list[TaskRow] = []
            for task in ordered_tasks:
                if task.status not in (TaskStatus.pending, TaskStatus.partial):
                    continue
                if task.due_date is not None and task.due_date < on_date:
                    rollover.append(task)
                elif is_working_today and (task.due_date is None or task.due_date == on_date):
                    fresh.append(task)

            plan_selection: list[TaskRow] = []
            if tasks_per_day > 0:
                for task in rollover + fresh:
                    if len(plan_selection) >= tasks_per_day:
                        break
                    plan_selection.append(task)
                    total_available += 1

            if plan_selection:
                selected_by_plan.append((plan, plan_selection, tasks_per_day, working_day_num))

        selected: list[TaskRow] = []
        for _plan, plan_tasks, _tasks_per_day, _wd in selected_by_plan:
            selected.extend(plan_tasks)

        return {
            "date": on_date,
            "tasks": selected,
            "total_available": total_available,
            "selected_count": len(selected),
            "max_tasks_per_day": largest_plan_slice,
            "daily_limit": total_available,
            "plans_queried": len(active_plans),
            "plans_working_day": plans_working_day,
            "locked": True,
            "extra_task_ids": [],
        }

    def _result_from_batch(self, user_id: UUID, on_date: date, batch: dict) -> dict:
        task_ids = [UUID(str(task_id)) for task_id in adaptive_store._safe_json_list(batch.get("task_ids"))]
        tasks = adaptive_store.get_tasks_by_ids(task_ids)
        metadata = adaptive_store._safe_json_dict(batch.get("metadata")) or {}
        extra_task_ids = adaptive_store._safe_json_list(batch.get("extra_task_ids"))
        daily_limit = int(batch.get("daily_limit") or len(task_ids))
        return {
            "date": on_date,
            "tasks": tasks,
            "total_available": daily_limit,
            "selected_count": len(tasks),
            "max_tasks_per_day": daily_limit,
            "daily_limit": daily_limit,
            "plans_queried": metadata.get("plans_queried", 0),
            "plans_working_day": metadata.get("plans_working_day", {}),
            "locked": True,
            "extra_task_ids": extra_task_ids,
        }

    def pull_extra_tasks(self, user_id: UUID, count: int, on_date: date | None = None) -> dict:
        """Manually add 1-3 extra tasks to today's locked batch."""
        if on_date is None:
            on_date = date.today()
        count = max(1, min(count, 3))

        batch = adaptive_store.get_daily_task_batch(user_id, on_date)
        if batch is None:
            self.get_today_tasks(user_id, on_date)
            batch = adaptive_store.get_daily_task_batch(user_id, on_date)

        existing_ids: set[UUID] = set()
        if batch is not None:
            existing_ids = {
                UUID(str(task_id))
                for task_id in adaptive_store._safe_json_list(batch.get("task_ids"))
            }

        active_plans = [
            p for p in adaptive_store.list_active_plans(user_id)
            if p.status == PlanStatus.active
        ]
        active_plans.sort(key=_plan_sort_key)

        pulled: list[TaskRow] = []
        for plan in active_plans:
            ordered_tasks = self._ordered_tasks_for_plan(user_id, plan)
            for task in ordered_tasks:
                if len(pulled) >= count:
                    break
                if task.id in existing_ids:
                    continue
                if task.status not in (TaskStatus.pending, TaskStatus.partial):
                    continue
                updated = adaptive_store.reschedule_task(task.id, on_date)
                pulled.append(updated or task)
                existing_ids.add(task.id)
            if len(pulled) >= count:
                break

        if pulled:
            adaptive_store.append_daily_task_batch_tasks(
                user_id=user_id,
                on_date=on_date,
                extra_task_ids=[task.id for task in pulled],
            )

        refreshed = adaptive_store.get_daily_task_batch(user_id, on_date)
        if refreshed is not None:
            return self._result_from_batch(user_id, on_date, refreshed)
        return self.get_today_tasks(user_id, on_date)

    def _ordered_tasks_for_plan(self, user_id: UUID, plan: PlanRow) -> list[TaskRow]:
        milestones = adaptive_store.get_milestones_for_plan(user_id, plan.id)
        ordered: list[TaskRow] = []
        seen_ids: set[UUID] = set()

        for milestone in milestones:
            ms_tasks = adaptive_store.get_tasks_for_milestone(user_id, milestone.id)
            ms_tasks.sort(key=lambda t: t.order_index)
            for task in ms_tasks:
                if task.id not in seen_ids:
                    ordered.append(task)
                    seen_ids.add(task.id)

        res = (
            adaptive_store.client.table("tasks")
            .select()
            .eq("plan_id", str(plan.id))
            .execute()
        )
        unassigned: list[TaskRow] = []
        for row in (res[1] if res and res[1] else []):
            task = adaptive_store._map_task(row)
            if task.id in seen_ids:
                continue
            unassigned.append(task)
            seen_ids.add(task.id)

        unassigned.sort(key=lambda t: (t.milestone_id is not None, t.order_index))
        ordered.extend(unassigned)
        return ordered

    def get_daily_tasks(self, user_id: UUID, on_date: date | None = None) -> dict:
        return self.get_today_tasks(user_id, on_date)

    def get_working_day_number(self, plan: PlanRow, on_date: date | None = None) -> int:
        """Public helper to get the current working day number for a plan."""
        return _current_working_day(plan, on_date or date.today())


scheduler_service = SchedulerService()
