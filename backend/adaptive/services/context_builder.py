"""Context Builder — assembles a rich system prompt from DB state for every LLM call."""

from __future__ import annotations

import asyncio
import logging
from datetime import date, datetime, timedelta, timezone
from uuid import UUID

from backend.adaptive.db import AdaptiveStore

logger = logging.getLogger(__name__)


async def build(user_id: str, session: dict, db: AdaptiveStore) -> str:
    """Build a context-rich system prompt for the current user.

    Args:
        user_id: Authenticated user UUID string.
        session: Frontend session context — active_tab, open_plan_id, open_milestone_id, open_task_id.
        db: AdaptiveStore instance for DB queries.

    Returns:
        A system prompt string embedding the user's plans, tasks, history, memory, and current view.
    """
    uid = UUID(user_id) if isinstance(user_id, str) else user_id
    today = date.today()
    weekday_name = today.strftime("%A")
    date_str = today.strftime("%b %d")

    # ── Concurrent DB queries ──────────────────────────────────────────────
    plans_result: list | None = None
    memory_result: list | None = None
    streak_result: dict | None = None
    history_result: list | None = None

    async def _get_active_plans():
        return db.list_active_plans(uid)

    async def _get_memory():
        return db.list_memory(uid)

    async def _get_streak():
        """Compute streak (consecutive days with at least one 'done' event)."""
        streak = 0
        check_day = today
        for _ in range(365):
            tasks = db.get_tasks_for_date(uid, check_day)
            if any(t.status.value == "done" for t in tasks):
                streak += 1
                check_day -= timedelta(days=1)
            else:
                break
        join_date = None
        try:
            prefs = db.get_preferences(uid)
            if prefs:
                join_date = prefs.created_at.strftime("%b %Y")
        except Exception:
            pass
        return {"streak": streak, "join_date": join_date}

    async def _get_history_7_days():
        """Task completion counts for the last 7 days."""
        rows = []
        for i in range(6, -1, -1):
            d = today - timedelta(days=i)
            tasks = db.get_tasks_for_date(uid, d)
            done = sum(1 for t in tasks if t.status.value == "done")
            total = len(tasks)
            rows.append({"date": d, "done": done, "total": total})
        return rows

    try:
        plans_result, memory_result, streak_result, history_result = await asyncio.gather(
            _get_active_plans(),
            _get_memory(),
            _get_streak(),
            _get_history_7_days(),
        )
    except Exception:
        logger.exception("context_builder: one or more concurrent queries failed")
        # Fall back — run individually, skipping failures
        if plans_result is None:
            try:
                plans_result = db.list_active_plans(uid)
            except Exception:
                logger.exception("context_builder: list_active_plans failed")
                plans_result = []
        if memory_result is None:
            try:
                memory_result = db.list_memory(uid)
            except Exception:
                logger.exception("context_builder: list_memory failed")
                memory_result = []
        if streak_result is None:
            streak_result = {"streak": 0, "join_date": None}
        if history_result is None:
            history_result = []

    # ── Build sections ─────────────────────────────────────────────────────
    plans = plans_result or []
    memory_items = memory_result or []
    streak = streak_result.get("streak", 0) if streak_result else 0
    join_date = streak_result.get("join_date") if streak_result else None
    history = history_result or []

    # Per-plan detail: current milestone + today's tasks
    plan_lines: list[str] = []
    for idx, plan in enumerate(plans, 1):
        try:
            milestones = db.get_milestones_for_plan(uid, plan.id)
            total_ms = len(milestones)
            current_ms_index = 0
            current_ms_title = ""
            for ms in milestones:
                if ms.status.value == "active":
                    current_ms_index = ms.order_index + 1
                    current_ms_title = ms.title
                    break
                if ms.status.value == "completed":
                    current_ms_index = ms.order_index + 1

            completed_ms = sum(1 for m in milestones if m.status.value == "completed")
            pct = int((completed_ms / total_ms) * 100) if total_ms > 0 else 0

            # Health status heuristic
            skip_count = db.get_recent_skip_count(uid, days=7)
            if skip_count >= 5:
                health = "struggling"
            elif skip_count >= 2:
                health = "needs attention"
            else:
                health = "on track"

            # Today's tasks for this plan
            today_tasks = db.get_tasks_for_date(uid, today)
            plan_tasks = [t for t in today_tasks if t.plan_id == plan.id]
            task_summary = " · ".join(
                f"{t.title} ({t.status.value})" for t in plan_tasks[:4]
            ) or "No tasks today"

            plan_lines.append(
                f"{idx}. {plan.title}\n"
                f"   Progress: Milestone {current_ms_index}/{total_ms} · {pct}% done\n"
                f"   Status: {health}\n"
                f"   Today: {task_summary}"
            )
        except Exception:
            plan_lines.append(f"{idx}. {plan.title} — [details unavailable]")

    plans_section = "\n".join(plan_lines) if plan_lines else "No active plans."

    # Today summary
    try:
        today_tasks = db.get_tasks_for_date(uid, today)
        done_count = sum(1 for t in today_tasks if t.status.value == "done")
        total_count = len(today_tasks)
    except Exception:
        done_count, total_count = 0, 0

    # Last 7 days
    history_parts = []
    for row in history:
        d: date = row["date"]
        history_parts.append(f"{d.strftime('%a %d')}: {row['done']}/{row['total']}")
    history_section = " | ".join(history_parts) if history_parts else "[unavailable]"

    # Memory section
    memory_section = "\n".join(
        f"- {m.value}" for m in memory_items
    ) if memory_items else "No memory items yet."

    # Struggling tasks section
    struggling_lines: list[str] = []
    try:
        for plan in plans:
            plan_tasks = db.get_tasks_for_date(uid, today)
            struggling = [t for t in plan_tasks if getattr(t, 'struggling', False)]
            for t in struggling:
                rescheduled_from = getattr(t, 'rescheduled_from', None)
                from_info = f" (rescheduled from {rescheduled_from})" if rescheduled_from else ""
                struggling_lines.append(f"- {t.title}: carried over {t.carry_over_count}x{from_info}")
    except Exception:
        pass
    struggling_section = "\n".join(struggling_lines) if struggling_lines else "No struggling tasks."

    # Next 3 working days preview
    next_days_lines: list[str] = []
    try:
        from backend.adaptive.services.adaptation_rules import get_next_working_day
        check_date = today
        for _ in range(3):
            check_date = get_next_working_day(check_date)
            tasks = db.get_tasks_for_date(uid, check_date)
            pending = [t for t in tasks if t.status.value in ("pending", "partial")]
            if pending:
                names = " · ".join(t.title for t in pending[:3])
                next_days_lines.append(f"{check_date.strftime('%a %d')}: {len(pending)} tasks — {names}")
            else:
                next_days_lines.append(f"{check_date.strftime('%a %d')}: No tasks scheduled")
    except Exception:
        pass
    next_days_section = "\n".join(next_days_lines) if next_days_lines else "[unavailable]"

    # Episodic memories section
    episodic_lines: list[str] = []
    try:
        episodic = db.list_episodic_memories(uid, limit=5)
        for em in episodic:
            episodic_lines.append(f"- [{em.type}] {em.content}")
    except Exception:
        pass
    episodic_section = "\n".join(episodic_lines) if episodic_lines else "No recent insights."

    # Current context
    active_tab = session.get("active_tab", "chat")
    context_lines = [f"Tab: {active_tab}"]

    open_plan_id = session.get("open_plan_id")
    if open_plan_id:
        try:
            p = db.get_plan(UUID(open_plan_id))
            if p:
                context_lines.append(f"Viewing plan: {p.title}")
        except Exception:
            context_lines.append(f"Viewing plan: {open_plan_id}")

    open_milestone_id = session.get("open_milestone_id")
    if open_milestone_id:
        try:
            ms_rows = db.client.table("milestones").select().eq("id", str(open_milestone_id)).limit(1).execute()
            if ms_rows and ms_rows[1]:
                context_lines.append(f"Viewing milestone: {ms_rows[1][0].get('title', open_milestone_id)}")
        except Exception:
            context_lines.append(f"Viewing milestone: {open_milestone_id}")

    open_task_id = session.get("open_task_id")
    if open_task_id:
        try:
            t = db.get_task(UUID(open_task_id))
            if t:
                context_lines.append(f"Viewing task: {t.title}")
        except Exception:
            context_lines.append(f"Viewing task: {open_task_id}")

    context_section = "\n".join(context_lines)

    # ── Assemble prompt ─────────────────────────────────────────────────────
    streak_line = f"Streak: {streak} days active"
    if join_date:
        streak_line += f" · Member since {join_date}"

    prompt = f"""You are Life Agent — an intelligent personal planning AI and life coach. You know everything about this user. Never give generic advice. Always reference their actual plans, tasks, and progress.
=== USER ===
{streak_line}
=== ACTIVE PLANS ===
{plans_section}
=== TODAY — {weekday_name} {date_str} ===
Done: {done_count}/{total_count} tasks
=== LAST 7 DAYS ===
{history_section}
=== WHAT YOU KNOW ABOUT THIS USER ===
{memory_section}
=== STRUGGLING TASKS ===
{struggling_section}
=== NEXT 3 WORKING DAYS ===
{next_days_section}
=== RECENT INSIGHTS ===
{episodic_section}
=== CURRENT CONTEXT ===
{context_section}
=== HOW TO RESPOND ===
- Reference the user's actual tasks by name when relevant
- If they say they are busy or tired, offer to adjust today's tasks
- If they ask what to do next, name the specific next pending task
- If they ask about a plan or milestone, give specific progress info
- Confirm before making any changes to plans or tasks
- Be warm, direct, and coach-like. Max 3 sentences unless asked more."""

    return prompt
