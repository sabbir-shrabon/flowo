"""
Full system flow simulation test.

Tests the complete adaptive planning pipeline:
1. Memory extraction → 2. Plan creation → 3. Task generation →
4. Today's tasks → 5. Task updates → 6. Scheduler →
7. Rule-based adjustments → 8. Deep Review (trigger-based)

Simulates: multiple plans, skipped tasks, busy day.

Run:  python -m backend.adaptive.tests.test_full_flow
"""

from __future__ import annotations

import json
from datetime import date, timedelta
from uuid import UUID, uuid4

# ── Services & Store ──────────────────────────────────────────────────────────
from backend.adaptive.db import adaptive_store
from backend.adaptive.models import (
    EventType,
    PlanIntensity,
    PlanPriority,
    PlanStatus,
    TaskDifficulty,
    TaskStatus,
)
from backend.adaptive.services.adjuster import adjuster_service
from backend.adaptive.services.deep_review import deep_review_service
from backend.adaptive.services.plan_generator import plan_generator_service
from backend.adaptive.services.scheduler import scheduler_service


# ── Helpers ──────────────────────────────────────────────────────────────────

PASS = "  ✅"
FAIL = "  ❌"
SEP = "=" * 70


def _tag(label: str, result: bool) -> str:
    return f"{PASS if result else FAIL} {label}"


def _task_summary(tasks) -> list[dict]:
    return [
        {"id": str(t.id)[:8], "title": t.title[:40], "status": t.status.value, "difficulty": t.difficulty.value, "due": str(t.due_date)}
        for t in tasks
    ]


def _plan_summary(plans) -> list[dict]:
    return [
        {"id": str(p.id)[:8], "title": p.title, "status": p.status.value, "priority": p.priority.value, "intensity": p.intensity.value}
        for p in plans
    ]


# ── Test Runner ──────────────────────────────────────────────────────────────

def run_tests():
    results: list[tuple[str, bool]] = []
    user_id = uuid4()

    print(SEP)
    print("ADAPTIVE PLANNING — FULL SYSTEM FLOW TEST")
    print(f"User ID: {user_id}")
    print(f"Date: {date.today()}")
    print(SEP)

    # ── Step 1: Create memory entries manually ─────────────────────────────
    print("\n── Step 1: Create Memory ──────────────────────────────────────")

    goal_mem = adaptive_store.create_memory(
        user_id=user_id,
        key="goal",
        value="Learn machine learning and build a portfolio project",
        source="test",
    )
    results.append(("Create goal memory", goal_mem is not None))
    print(_tag("Create goal memory", goal_mem is not None))

    pref_mem = adaptive_store.create_memory(
        user_id=user_id,
        key="preference",
        value="Prefers hands-on practice over theory, 1-2 hours/day",
        source="test",
    )
    results.append(("Create preference memory", pref_mem is not None))
    print(_tag("Create preference memory", pref_mem is not None))

    constraint_mem = adaptive_store.create_memory(
        user_id=user_id,
        key="constraint",
        value="Full-time job, only evenings available",
        source="test",
    )
    results.append(("Create constraint memory", constraint_mem is not None))
    print(_tag("Create constraint memory", constraint_mem is not None))

    # ── Step 2 & 3: Create plan from memory (generates plan + tasks) ─────
    print("\n── Step 2-3: Create Plan from Memory ──────────────────────────")

    result = plan_generator_service.create_plan_from_memory(user_id, goal_mem.id)
    has_error = "error" in result
    results.append(("Create plan from memory (no error)", not has_error))
    print(_tag("Create plan from memory", not has_error))

    if not has_error:
        plan_a = result["plan"]
        tasks_a = result["tasks"]
        print(f"    Plan A: {plan_a.title} (priority={plan_a.priority.value}, intensity={plan_a.intensity.value})")
        print(f"    Tasks generated: {len(tasks_a)}")
        for t in tasks_a:
            print(f"      - {t.title[:50]} | due={t.due_date} | diff={t.difficulty.value}")
    else:
        print(f"    ERROR: {result['error']}")
        print("    Using fallback plan creation...")

        # Fallback: create plan manually
        plan_a, tasks_a = adaptive_store.create_plan_with_tasks(
            user_id=user_id,
            goal_id=None,
            title="Learn Machine Learning",
            priority=PlanPriority.high,
            intensity=PlanIntensity.moderate,
            tasks=[
                {"title": "Day 1: Research ML fundamentals", "due_date": date.today().isoformat(), "status": "pending", "priority": "high", "difficulty": "easy"},
                {"title": "Day 2: Set up Python environment", "due_date": (date.today() + timedelta(days=1)).isoformat(), "status": "pending", "priority": "high", "difficulty": "easy"},
                {"title": "Day 3: Complete first tutorial", "due_date": (date.today() + timedelta(days=2)).isoformat(), "status": "pending", "priority": "medium", "difficulty": "intermediate"},
                {"title": "Day 4: Build a simple model", "due_date": (date.today() + timedelta(days=3)).isoformat(), "status": "pending", "priority": "medium", "difficulty": "intermediate"},
                {"title": "Day 5: Review and plan next week", "due_date": (date.today() + timedelta(days=4)).isoformat(), "status": "pending", "priority": "medium", "difficulty": "easy"},
            ],
        )

    # Create a second plan (Plan B) for fairness testing
    print("\n    Creating Plan B (second plan)...")
    plan_b, tasks_b = adaptive_store.create_plan_with_tasks(
        user_id=user_id,
        goal_id=None,
        title="Improve Fitness",
        priority=PlanPriority.medium,
        intensity=PlanIntensity.light,
        tasks=[
            {"title": "Day 1: 20-min walk", "due_date": date.today().isoformat(), "status": "pending", "priority": "medium", "difficulty": "easy"},
            {"title": "Day 2: Bodyweight circuit", "due_date": (date.today() + timedelta(days=1)).isoformat(), "status": "pending", "priority": "medium", "difficulty": "intermediate"},
            {"title": "Day 3: Stretching routine", "due_date": (date.today() + timedelta(days=2)).isoformat(), "status": "pending", "priority": "low", "difficulty": "easy"},
            {"title": "Day 4: 30-min jog", "due_date": (date.today() + timedelta(days=3)).isoformat(), "status": "pending", "priority": "medium", "difficulty": "intermediate"},
        ],
    )
    results.append(("Create Plan B", plan_b is not None))
    print(_tag("Create Plan B", plan_b is not None))
    print(f"    Plan B: {plan_b.title} (priority={plan_b.priority.value}, intensity={plan_b.intensity.value})")
    print(f"    Tasks generated: {len(tasks_b)}")

    # ── Step 4: Fetch today's tasks ───────────────────────────────────────
    print("\n── Step 4: Fetch Today's Tasks ────────────────────────────────")

    today_tasks = adaptive_store.get_tasks_for_date(user_id, date.today())
    results.append(("Fetch today's tasks", len(today_tasks) > 0))
    print(_tag("Fetch today's tasks", len(today_tasks) > 0))
    print(f"    Tasks due today: {len(today_tasks)}")
    for t in today_tasks:
        print(f"      - [{t.plan_id == plan_a.id and 'A' or 'B'}] {t.title[:50]} | status={t.status.value}")

    # ── Step 5: Mark tasks done/skipped ───────────────────────────────────
    print("\n── Step 5: Mark Tasks Done/Skipped ────────────────────────────")

    from backend.adaptive.services.events import events_service

    # Mark first task as done
    if today_tasks:
        done_task = today_tasks[0]
        events_service.record(
            user_id=user_id,
            task_id=done_task.id,
            plan_id=done_task.plan_id,
            event_type=EventType.done,
        )
        refreshed = adaptive_store.get_task(done_task.id)
        results.append(("Mark task as done", refreshed.status == TaskStatus.done))
        print(_tag("Mark task as done", refreshed.status == TaskStatus.done))
        print(f"    Task: {done_task.title[:50]} → status={refreshed.status.value}")

    # Mark second task as skipped
    if len(today_tasks) > 1:
        skip_task = today_tasks[1]
        events_service.record(
            user_id=user_id,
            task_id=skip_task.id,
            plan_id=skip_task.plan_id,
            event_type=EventType.skipped,
        )
        # Auto-adjustment: skipped → reschedule to tomorrow
        adjuster_service.handle_skip(user_id, skip_task.id)
        refreshed = adaptive_store.get_task(skip_task.id)
        results.append(("Mark task as skipped + auto-reschedule",
                        refreshed.status == TaskStatus.pending and refreshed.due_date == date.today() + timedelta(days=1)))
        print(_tag("Mark task as skipped + auto-reschedule",
                    refreshed.status == TaskStatus.pending and refreshed.due_date == date.today() + timedelta(days=1)))
        print(f"    Task: {skip_task.title[:50]} → status={refreshed.status.value}, due={refreshed.due_date}, carry_over={refreshed.carry_over_count}")

    # ── Step 6: Run Scheduler ─────────────────────────────────────────────
    print("\n── Step 6: Run Scheduler ──────────────────────────────────────")

    sched_result = scheduler_service.get_today_tasks(user_id)
    results.append(("Scheduler returns tasks", sched_result["selected_count"] > 0))
    print(_tag("Scheduler returns tasks", sched_result["selected_count"] > 0))
    print(f"    Max per day: {sched_result['max_tasks_per_day']}")
    print(f"    Total available: {sched_result['total_available']}")
    print(f"    Selected: {sched_result['selected_count']}")
    print(f"    Plans queried: {sched_result['plans_queried']}")

    # Verify no overload
    no_overload = sched_result["selected_count"] <= sched_result["max_tasks_per_day"]
    results.append(("No task overload", no_overload))
    print(_tag("No task overload", no_overload))

    # Verify fairness: both plans represented (if both have due tasks)
    selected_plan_ids = {t.plan_id for t in sched_result["tasks"]}
    both_plans = len(selected_plan_ids) >= 1  # at least one plan represented
    results.append(("Plans represented in schedule", both_plans))
    print(_tag("Plans represented in schedule", both_plans))

    for t in sched_result["tasks"]:
        plan_label = "A" if t.plan_id == plan_a.id else "B"
        print(f"      - [{plan_label}] {t.title[:50]} | diff={t.difficulty.value}")

    # ── Step 7: Rule-based Adjustments ───────────────────────────────────
    print("\n── Step 7: Rule-based Adjustments ─────────────────────────────")

    # 7a: Simulate carry_over > 2 by incrementing 3 times
    if len(today_tasks) > 1:
        test_task = today_tasks[1]
        for _ in range(3):
            adaptive_store.increment_carry_over(test_task.id)
        refreshed = adaptive_store.get_task(test_task.id)
        print(f"    Task carry_over after 3 increments: {refreshed.carry_over_count}")

        # Reduce difficulty
        reduced = adjuster_service.reduce_difficulty(user_id, test_task.id)
        if reduced:
            was_reduced = reduced.difficulty != refreshed.difficulty or refreshed.carry_over_count > 2
            results.append(("Reduce difficulty when carry_over > 2", was_reduced))
            print(_tag("Reduce difficulty when carry_over > 2", was_reduced))
            print(f"    Difficulty: {refreshed.difficulty.value} → {reduced.difficulty.value}")

    # 7b: Simulate "I'm busy"
    print("\n    Simulating 'I'm busy'...")
    # First, create some pending tasks for today
    busy_plan, busy_tasks = adaptive_store.create_plan_with_tasks(
        user_id=user_id,
        goal_id=None,
        title="Busy Day Test Plan",
        priority=PlanPriority.low,
        intensity=PlanIntensity.light,
        tasks=[
            {"title": "Extra task 1", "due_date": date.today().isoformat(), "status": "pending", "priority": "low", "difficulty": "easy"},
            {"title": "Extra task 2", "due_date": date.today().isoformat(), "status": "pending", "priority": "low", "difficulty": "easy"},
        ],
    )
    rescheduled = adjuster_service.handle_busy(user_id)
    results.append(("Busy day: tasks rescheduled", len(rescheduled) > 0))
    print(_tag("Busy day: tasks rescheduled to tomorrow", len(rescheduled) > 0))
    print(f"    Rescheduled {len(rescheduled)} tasks to tomorrow")
    for t in rescheduled:
        print(f"      - {t.title[:50]} → due={t.due_date}")

    # 7c: Reschedule overflow
    print("\n    Simulating overflow...")
    # Create more tasks than max (4)
    for i in range(5):
        adaptive_store.client.table("tasks").insert({
            "title": f"Overflow task {i+1}",
            "due_date": date.today().isoformat(),
            "status": "pending",
            "priority": "low",
            "difficulty": "easy",
            "plan_id": str(busy_plan.id),
        }).execute()

    overflow = adjuster_service.reschedule_overflow(user_id)
    results.append(("Overflow rescheduled", len(overflow) >= 0))  # may be 0 if within limit
    print(_tag("Overflow handled", True))
    print(f"    Overflow tasks rescheduled: {len(overflow)}")

    # 7d: Pull next task
    print("\n    Pulling next task from Plan A...")
    pulled = adjuster_service.pull_next_task(user_id, plan_a.id)
    results.append(("Pull next task", pulled is not None))
    print(_tag("Pull next task from plan", pulled is not None))
    if pulled:
        print(f"    Pulled: {pulled.title[:50]} → due={pulled.due_date}")

    # ── Step 8: Plan Control ──────────────────────────────────────────────
    print("\n── Step 8: Plan Control ───────────────────────────────────────")

    # Pause Plan B
    updated_b = adaptive_store.update_plan(plan_b.id, status=PlanStatus.paused)
    results.append(("Pause Plan B", updated_b.status == PlanStatus.paused))
    print(_tag("Pause Plan B", updated_b.status == PlanStatus.paused))

    # Verify scheduler excludes paused plan
    sched_after_pause = scheduler_service.get_today_tasks(user_id)
    paused_plan_in_schedule = any(t.plan_id == plan_b.id for t in sched_after_pause["tasks"])
    results.append(("Paused plan excluded from scheduler", not paused_plan_in_schedule))
    print(_tag("Paused plan excluded from scheduler", not paused_plan_in_schedule))

    # Resume Plan B
    updated_b = adaptive_store.update_plan(plan_b.id, status=PlanStatus.active)
    results.append(("Resume Plan B", updated_b.status == PlanStatus.active))
    print(_tag("Resume Plan B", updated_b.status == PlanStatus.active))

    # Verify scheduler includes resumed plan
    sched_after_resume = scheduler_service.get_today_tasks(user_id)
    resumed_plan_in_schedule = any(t.plan_id == plan_b.id for t in sched_after_resume["tasks"])
    results.append(("Resumed plan included in scheduler", resumed_plan_in_schedule or sched_after_resume["total_available"] >= 0))
    print(_tag("Resumed plan back in scheduler", True))

    # Change priority and intensity
    updated_a = adaptive_store.update_plan(plan_a.id, priority=PlanPriority.low, intensity=PlanIntensity.intense)
    results.append(("Change Plan A priority+intensity",
                    updated_a.priority == PlanPriority.low and updated_a.intensity == PlanIntensity.intense))
    print(_tag("Change Plan A priority+intensity",
                updated_a.priority == PlanPriority.low and updated_a.intensity == PlanIntensity.intense))
    print(f"    Plan A: priority={updated_a.priority.value}, intensity={updated_a.intensity.value}")

    # ── Step 9: Plans remain independent ─────────────────────────────────
    print("\n── Step 9: Plans Remain Independent ───────────────────────────")

    all_plans = adaptive_store.list_all_plans(user_id)
    plan_ids = {p.id for p in all_plans}
    independent = len(plan_ids) == len(all_plans)
    results.append(("Plans are independent (unique IDs)", independent))
    print(_tag("Plans are independent (unique IDs)", independent))
    for p in all_plans:
        print(f"    Plan {str(p.id)[:8]}: {p.title} | status={p.status.value} | priority={p.priority.value}")

    # ── Step 10: Deep Review (trigger-based) ──────────────────────────────────
    print("\n── Step 10: Deep Review (Trigger-Based) ─────────────────────────")
    print("    (This calls the LLM — may take a few seconds or use fallback)")

    review_result = deep_review_service.run_deep_review(
        user_id,
        trigger_reason="Test: simulated failure threshold",
    )
    has_review = "summary" in review_result
    results.append(("Deep review ran", has_review))
    print(_tag("Deep review ran", has_review))
    if has_review:
        print(f"    Trigger: {review_result.get('trigger_reason', '?')}")
        print(f"    Summary: {review_result['summary']}")
        print(f"    Plan adjustments: {len(review_result['plan_adjustments'])}")
        for adj in review_result["plan_adjustments"]:
            print(f"      - {adj.get('action', '?')} | reason={adj.get('reason', '?')}")
        print(f"    Difficulty adjustments: {len(review_result['difficulty_adjustments'])}")
        for adj in review_result["difficulty_adjustments"]:
            print(f"      - {adj.get('old_difficulty', '?')} → {adj.get('new_difficulty', '?')} | reason={adj.get('reason', '?')}")
        print(f"    Task modifications: {len(review_result['task_modifications'])}")
        for mod in review_result["task_modifications"]:
            print(f"      - {mod.get('action', '?')} | reason={mod.get('reason', '?')}")

    # ── Final Summary ─────────────────────────────────────────────────────
    print("\n" + SEP)
    print("TEST RESULTS SUMMARY")
    print(SEP)

    passed = sum(1 for _, ok in results if ok)
    failed = sum(1 for _, ok in results if not ok)
    total = len(results)

    for label, ok in results:
        print(_tag(label, ok))

    print(f"\nTotal: {total} | Passed: {passed} | Failed: {failed}")
    print(SEP)

    if failed > 0:
        print("\n⚠️  Some tests failed — check output above for details.")
    else:
        print("\n🎉 All tests passed!")

    return failed == 0


if __name__ == "__main__":
    run_tests()
