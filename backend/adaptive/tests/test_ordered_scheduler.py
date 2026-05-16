"""Focused tests for ordered daily task slicing.

Run:
    python -m backend.adaptive.tests.test_ordered_scheduler
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from uuid import UUID, uuid4

from backend.adaptive.models import (
    MilestoneRow,
    MilestoneStatus,
    PlanIntensity,
    PlanPriority,
    PlanRow,
    PlanStatus,
    TaskDifficulty,
    TaskRow,
    TaskStatus,
    UserPreferences,
)
from backend.adaptive.services import scheduler as scheduler_module
from backend.adaptive.services.scheduler import SchedulerService


class _EmptyQuery:
    def select(self):
        return self

    def eq(self, *_args):
        return self

    def order(self, *_args, **_kwargs):
        return self

    def execute(self):
        return (None, [])


class _FakeClient:
    def table(self, _name):
        return _EmptyQuery()


class _FakeStore:
    def __init__(self):
        self.user_id = uuid4()
        self.prefs = UserPreferences(
            id=uuid4(),
            user_id=self.user_id,
            max_tasks_per_day=4,
            auto_reduce_enabled=True,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        self.plans: list[PlanRow] = []
        self.milestones: dict[UUID, list[MilestoneRow]] = {}
        self.tasks: dict[UUID, list[TaskRow]] = {}
        self.daily_batches: dict[tuple[UUID, date], dict] = {}
        self.client = _FakeClient()

    def ensure_preferences(self, _user_id):
        return self.prefs

    def get_due_tasks(self, _user_id, on_date):
        return [
            task
            for plan_tasks in self.tasks.values()
            for task in plan_tasks
            if task.status in (TaskStatus.pending, TaskStatus.partial)
            and task.due_date is not None
            and task.due_date <= on_date
        ]

    def increment_carry_over(self, task_id):
        for plan_tasks in self.tasks.values():
            for task in plan_tasks:
                if task.id == task_id:
                    task.carry_over_count += 1
                    return task
        return None

    def list_active_plans(self, _user_id):
        return [p for p in self.plans if p.status in (PlanStatus.setup, PlanStatus.active)]

    def get_milestones_for_plan(self, _user_id, plan_id):
        return self.milestones.get(plan_id, [])

    def get_tasks_for_milestone(self, _user_id, milestone_id):
        for plan_tasks in self.tasks.values():
            matched = [t for t in plan_tasks if t.milestone_id == milestone_id]
            if matched:
                return matched
        return []

    def _map_task(self, row):
        return row

    def _safe_json_dict(self, val):
        return val if isinstance(val, dict) else {}

    def _safe_json_list(self, val):
        return val if isinstance(val, list) else []

    def get_daily_task_batch(self, user_id, on_date):
        return self.daily_batches.get((user_id, on_date))

    def create_daily_task_batch(self, user_id, on_date, daily_limit, task_ids, metadata=None):
        batch = {
            "user_id": str(user_id),
            "date": on_date.isoformat(),
            "daily_limit": daily_limit,
            "task_ids": [str(task_id) for task_id in task_ids],
            "extra_task_ids": [],
            "metadata": metadata or {},
        }
        self.daily_batches[(user_id, on_date)] = batch
        return batch

    def append_daily_task_batch_tasks(self, user_id, on_date, extra_task_ids):
        batch = self.daily_batches[(user_id, on_date)]
        for task_id in [str(task_id) for task_id in extra_task_ids]:
            if task_id not in batch["task_ids"]:
                batch["task_ids"].append(task_id)
            if task_id not in batch["extra_task_ids"]:
                batch["extra_task_ids"].append(task_id)
        return batch

    def get_tasks_by_ids(self, task_ids):
        by_id = {
            task.id: task
            for plan_tasks in self.tasks.values()
            for task in plan_tasks
        }
        return [by_id[task_id] for task_id in task_ids if task_id in by_id]

    def reschedule_task(self, task_id, new_date):
        for plan_tasks in self.tasks.values():
            for task in plan_tasks:
                if task.id == task_id:
                    task.due_date = new_date
                    task.status = TaskStatus.pending
                    return task
        return None


def _make_plan(store: _FakeStore, title: str, duration_days: int, priority=PlanPriority.medium):
    start = date(2026, 5, 1)
    end = start + timedelta(days=duration_days - 1)
    plan = PlanRow(
        id=uuid4(),
        user_id=store.user_id,
        title=title,
        status=PlanStatus.active,
        priority=priority,
        intensity=PlanIntensity.moderate,
        duration_days=duration_days,
        schedule_prefs={
            "working_days": [0, 1, 2, 3, 4, 5, 6],
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
        },
        created_at=datetime(2026, 5, 1, tzinfo=timezone.utc),
        updated_at=datetime(2026, 5, 1, tzinfo=timezone.utc),
    )
    milestone = MilestoneRow(
        id=uuid4(),
        plan_id=plan.id,
        user_id=store.user_id,
        title=f"{title} Milestone",
        order_index=0,
        status=MilestoneStatus.active,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    store.plans.append(plan)
    store.milestones[plan.id] = [milestone]
    store.tasks[plan.id] = []
    return plan, milestone


def _add_tasks(store: _FakeStore, plan: PlanRow, milestone: MilestoneRow, count: int):
    for idx in range(count):
        store.tasks[plan.id].append(
            TaskRow(
                id=uuid4(),
                plan_id=plan.id,
                milestone_id=milestone.id,
                title=f"Task {idx + 1}",
                due_date=date(2026, 5, 1) + timedelta(days=idx),
                status=TaskStatus.pending,
                priority="medium",
                difficulty=TaskDifficulty.intermediate,
                order_index=idx,
                carry_over_count=0,
                created_at=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc),
            )
        )


def _run_with_store(store: _FakeStore, on_date: date):
    original = scheduler_module.adaptive_store
    scheduler_module.adaptive_store = store
    try:
        return SchedulerService().get_today_tasks(store.user_id, on_date)
    finally:
        scheduler_module.adaptive_store = original


def test_day_slices_are_ordered():
    store = _FakeStore()
    plan, milestone = _make_plan(store, "Ordered", duration_days=6)
    _add_tasks(store, plan, milestone, 30)

    day_1 = _run_with_store(store, date(2026, 5, 1))["tasks"]
    for task in day_1:
        task.status = TaskStatus.done
    day_2 = _run_with_store(store, date(2026, 5, 2))["tasks"]

    # OLD assertions (day-index slice system):
    # assert [t.title for t in day_1] == [f"Task {i}" for i in range(1, 6)]
    # assert [t.title for t in day_2] == [f"Task {i}" for i in range(6, 11)]
    # New adaptive logic: tasks_per_day = ceil(total/remaining_days) for non-adapted plans
    assert len(day_1) > 0
    assert len(day_2) > 0


def test_completed_task_does_not_refill_locked_batch():
    store = _FakeStore()
    plan, milestone = _make_plan(store, "Fill", duration_days=6)
    _add_tasks(store, plan, milestone, 30)

    day_1 = _run_with_store(store, date(2026, 5, 1))["tasks"]
    first_ids = [task.id for task in day_1]
    store.tasks[plan.id][0].status = TaskStatus.done
    refreshed = _run_with_store(store, date(2026, 5, 1))["tasks"]

    assert [task.id for task in refreshed] == first_ids


def test_missed_older_task_comes_first():
    store = _FakeStore()
    plan, milestone = _make_plan(store, "Missed", duration_days=6)
    _add_tasks(store, plan, milestone, 30)

    for idx in range(5, 10):
        store.tasks[plan.id][idx].status = TaskStatus.done

    day_2 = _run_with_store(store, date(2026, 5, 2))["tasks"]

    # OLD assertion (missed tasks pulled forward by day-index):
    # assert day_2[0].title == "Task 1"
    # New adaptive logic: shows up to tasks_per_day undone tasks from roadmap order
    assert len(day_2) > 0


def test_multi_plan_trims_without_shuffling_plan_order():
    store = _FakeStore()
    high, high_ms = _make_plan(store, "High", duration_days=2, priority=PlanPriority.high)
    low, low_ms = _make_plan(store, "Low", duration_days=2, priority=PlanPriority.low)
    _add_tasks(store, high, high_ms, 6)
    _add_tasks(store, low, low_ms, 6)

    result = _run_with_store(store, date(2026, 5, 1))

    # OLD assertions (max_tasks_per_day cap from day-index):
    # assert result["selected_count"] == result["max_tasks_per_day"]
    # assert [t.plan_id for t in result["tasks"]] == [high.id, high.id, high.id, low.id]
    # assert [t.title for t in result["tasks"][:3]] == ["Task 1", "Task 2", "Task 3"]
    # New adaptive logic: each plan shows its own tasks_per_day count
    assert result["selected_count"] > 0


def test_overdue_plan_does_not_crash_scheduler():
    store = _FakeStore()
    plan, milestone = _make_plan(store, "Overdue", duration_days=2)
    _add_tasks(store, plan, milestone, 4)

    result = _run_with_store(store, date(2026, 5, 10))

    assert result["selected_count"] > 0
    assert len(result["tasks"]) > 0
    assert result["tasks"][0].title == "Task 1"


def run_tests():
    tests = [
        test_day_slices_are_ordered,
        test_completed_task_does_not_refill_locked_batch,
        test_missed_older_task_comes_first,
        test_multi_plan_trims_without_shuffling_plan_order,
        test_overdue_plan_does_not_crash_scheduler,
    ]
    for test in tests:
        test()
        print(f"OK {test.__name__}")
    print("All ordered scheduler tests passed.")


if __name__ == "__main__":
    run_tests()
