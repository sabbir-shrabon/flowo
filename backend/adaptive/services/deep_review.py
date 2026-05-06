"""Trigger-Based Deep Review — replaces the old Sunday-cron EOD review.

Instead of running on a fixed schedule, a deep review is triggered when:
1. Milestone completed — user hit a milestone, review plan progress & next steps
2. Failure threshold — user skipped/missed N tasks in a row, needs plan adjustment

This prevents server spikes and provides advice when it's actually needed.
"""

from __future__ import annotations

import json
import logging
from datetime import date, datetime, timedelta, timezone
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import (
    EventType,
    MilestoneStatus,
    PlanIntensity,
    PlanPriority,
    PlanRow,
    TaskDifficulty,
    TaskRow,
    TaskStatus,
)
from backend.lib.llm import chatResponse

logger = logging.getLogger(__name__)

# ── Failure thresholds ────────────────────────────────────────────────────────
CONSECUTIVE_SKIP_THRESHOLD = 3   # 3+ skips in a row triggers deep review
WEEKLY_MISS_RATE_THRESHOLD = 0.6 # 60%+ miss rate over 7 days triggers deep review


# ── Deep Review Prompt ───────────────────────────────────────────────────────

DEEP_REVIEW_PROMPT = """You are an adaptive planning assistant performing a deep review.

This review was triggered because: {trigger_reason}

Analyze the user's recent activity and produce a structured adjustment plan.

INPUT SUMMARY:
- Completed tasks: {completed}
- Missed/skipped tasks: {missed}
- Partially done tasks: {partial}
- User feedback: {feedback}
- Plan summaries: {plan_summaries}

Your job:
1. Rebalance plans: if one plan is consistently missed, lower its intensity or priority
2. Adjust difficulty: if tasks were too hard (skipped/partial), reduce difficulty; if all done easily, increase
3. Modify upcoming tasks: reschedule, merge, split, or add tasks as needed
4. Suggest next steps based on the trigger reason

Return EXACTLY a JSON object with these keys (no markdown, no code fences):

{{
  "plan_adjustments": [
    {{
      "plan_id": "uuid-string",
      "action": "reduce_intensity" | "increase_intensity" | "reduce_priority" | "pause",
      "reason": "short explanation"
    }}
  ],
  "difficulty_adjustments": [
    {{
      "task_id": "uuid-string",
      "new_difficulty": "easy" | "intermediate" | "hard",
      "reason": "short explanation"
    }}
  ],
  "task_modifications": [
    {{
      "action": "reschedule" | "add" | "remove" | "merge",
      "task_id": "uuid-string or null for add",
      "plan_id": "uuid-string",
      "title": "string (for add/merge)",
      "due_in_days": 1,
      "difficulty": "easy" | "intermediate" | "hard",
      "reason": "short explanation"
    }}
  ],
  "summary": "1-2 sentence summary and what you changed"
}}

Rules:
- Only include items that need changing, not everything
- "reschedule" moves a task to a later day (set due_in_days)
- "add" creates a new task (task_id is null, provide title)
- "remove" deletes a task that is no longer needed
- "merge" combines two tasks into one (provide new title, task_id is the primary one)
- Be conservative: only adjust when the data clearly supports it
- Do NOT modify completed tasks
- Consider the trigger reason when making recommendations"""


class DeepReviewService:
    """Trigger-based deep review. No cron, no schedule — only fires when needed."""

    def on_milestone_completed(self, user_id: UUID, milestone_id: UUID) -> dict | None:
        """Trigger a deep review when a milestone is completed.

        Reviews plan progress and suggests adjustments for the next milestone.
        """
        # Fetch milestone directly — no get_milestone(id) helper exists
        res = (
            adaptive_store.client.table("milestones")
            .select()
            .eq("id", str(milestone_id))
            .eq("user_id", str(user_id))
            .limit(1)
            .execute()
        )
        if not res or not res[1]:
            return None

        row = res[1][0]
        milestone_title = row.get("title", "Unknown")
        plan_id_str = row.get("plan_id")

        plan = None
        plan_title = "Unknown"
        plan_id_filter = None
        if plan_id_str:
            try:
                plan_id_filter = UUID(plan_id_str)
                plan = adaptive_store.get_plan(plan_id_filter)
                plan_title = plan.title if plan and plan.title else "Unknown"
            except ValueError:
                pass

        return self.run_deep_review(
            user_id,
            trigger_reason=f"Milestone '{milestone_title}' completed in plan '{plan_title}'",
            plan_id_filter=plan_id_filter,
        )

    def on_failure_threshold(self, user_id: UUID) -> dict | None:
        """Trigger a deep review when the user hits a failure threshold.

        Checks:
        1. 3+ consecutive days with high skip/miss rate
        2. 60%+ miss rate over the past 7 days
        """
        if not self._check_failure_threshold(user_id):
            return None

        return self.run_deep_review(
            user_id,
            trigger_reason="Failure threshold reached: user is struggling with tasks",
        )

    def check_and_trigger(self, user_id: UUID) -> dict | None:
        """Convenience method: check failure thresholds and trigger if needed.

        Called by task_observer after task status changes.
        """
        return self.on_failure_threshold(user_id)

    def run_deep_review(self, user_id: UUID, trigger_reason: str, plan_id_filter: UUID | None = None) -> dict:
        """LLM-assisted deep review. Gathers recent data and proposes adjustments."""
        today = date.today()
        lookback = 7  # Always look at past 7 days of data

        # Gather past week's tasks
        completed, missed, partial = [], [], []
        for offset in range(lookback):
            d = today - timedelta(days=lookback - offset)
            tasks = adaptive_store.get_tasks_for_date(user_id, d)
            for t in tasks:
                if plan_id_filter and t.plan_id != plan_id_filter:
                    continue
                snap = self._task_snapshot(t)
                if t.status == TaskStatus.done:
                    completed.append(snap)
                elif t.status == TaskStatus.skipped:
                    missed.append(snap)
                elif t.status == TaskStatus.partial:
                    partial.append(snap)

        # Gather feedback
        since = datetime.combine(today - timedelta(days=lookback), datetime.min.time()).replace(tzinfo=timezone.utc)
        feedback_events = adaptive_store.get_events_for_user(
            user_id, event_type=EventType.feedback, since=since,
        )
        feedback = [
            {"task_id": str(e.task_id), "rating": e.feedback_rating, "text": e.feedback_text}
            for e in feedback_events
            if e.feedback_rating is not None or e.feedback_text
        ]

        active_plans = adaptive_store.list_active_plans(user_id)
        if plan_id_filter:
            active_plans = [p for p in active_plans if p.id == plan_id_filter]
        plan_summaries = [self._plan_snapshot(p, user_id) for p in active_plans]

        # Call LLM
        prompt = DEEP_REVIEW_PROMPT.format(
            trigger_reason=trigger_reason,
            completed=json.dumps(completed) if completed else "[]",
            missed=json.dumps(missed) if missed else "[]",
            partial=json.dumps(partial) if partial else "[]",
            feedback=json.dumps(feedback) if feedback else "none",
            plan_summaries=json.dumps(plan_summaries),
        )

        try:
            content = chatResponse(prompt)
            content = content.strip()
            if content.startswith("```json"):
                content = content[7:]
            if content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()
            parsed = json.loads(content)
        except Exception as exc:
            logger.error("Deep review LLM failed: %s", exc)
            return self._fallback_adjustment(user_id, missed, partial, trigger_reason)

        # Apply adjustments
        applied = {
            "trigger_reason": trigger_reason,
            "plan_adjustments": [],
            "difficulty_adjustments": [],
            "task_modifications": [],
            "summary": parsed.get("summary", ""),
            "llm_raw": parsed,
        }

        for adj in parsed.get("plan_adjustments", []):
            result = self._apply_plan_adjustment(user_id, adj)
            if result:
                applied["plan_adjustments"].append(result)

        for adj in parsed.get("difficulty_adjustments", []):
            result = self._apply_difficulty_adjustment(user_id, adj)
            if result:
                applied["difficulty_adjustments"].append(result)

        for mod in parsed.get("task_modifications", []):
            result = self._apply_task_modification(user_id, mod)
            if result:
                applied["task_modifications"].append(result)

        # Save review summary
        try:
            adaptive_store.save_daily_summary(
                user_id, today,
                f"[Deep Review] {applied.get('summary', '')}",
                {"type": "deep_review", "trigger": trigger_reason,
                 "plan_adjustments": len(applied["plan_adjustments"]),
                 "difficulty_adjustments": len(applied["difficulty_adjustments"]),
                 "task_modifications": len(applied["task_modifications"])},
            )
        except Exception as e:
            logger.warning("Failed to save deep review summary: %s", e)

        return applied

    # ── Failure threshold checks ────────────────────────────────────────────

    def _check_failure_threshold(self, user_id: UUID) -> bool:
        """Check if the user has hit a failure threshold."""
        today = date.today()

        # Check 1: consecutive days with high skip/miss rate
        consecutive_bad_days = 0
        for days_ago in range(5):
            d = today - timedelta(days=days_ago + 1)
            tasks = adaptive_store.get_tasks_for_date(user_id, d)
            if not tasks:
                consecutive_bad_days = 0
                continue
            done = sum(1 for t in tasks if t.status == TaskStatus.done)
            miss_rate = 1.0 - (done / len(tasks))
            if miss_rate >= 0.5:
                consecutive_bad_days += 1
            else:
                consecutive_bad_days = 0

        if consecutive_bad_days >= CONSECUTIVE_SKIP_THRESHOLD:
            return True

        # Check 2: 7-day miss rate
        total, done_total = 0, 0
        for days_ago in range(7):
            d = today - timedelta(days=days_ago + 1)
            tasks = adaptive_store.get_tasks_for_date(user_id, d)
            total += len(tasks)
            done_total += sum(1 for t in tasks if t.status == TaskStatus.done)

        if total > 0 and (1.0 - done_total / total) >= WEEKLY_MISS_RATE_THRESHOLD:
            return True

        return False

    # ── Apply helpers ────────────────────────────────────────────────────────

    def _apply_plan_adjustment(self, user_id: UUID, adj: dict) -> dict | None:
        plan_id_str = adj.get("plan_id")
        action = adj.get("action", "")
        reason = adj.get("reason", "")
        if not plan_id_str:
            return None

        try:
            plan_id = UUID(plan_id_str)
        except ValueError:
            return None

        plan = adaptive_store.get_plan(plan_id)
        if plan is None or plan.user_id != user_id:
            return None

        intensity = None
        priority = None
        status = None

        if action == "reduce_intensity":
            downgrade = {PlanIntensity.intense: PlanIntensity.moderate, PlanIntensity.moderate: PlanIntensity.light}
            intensity = downgrade.get(plan.intensity)
        elif action == "increase_intensity":
            upgrade = {PlanIntensity.light: PlanIntensity.moderate, PlanIntensity.moderate: PlanIntensity.intense}
            intensity = upgrade.get(plan.intensity)
        elif action == "reduce_priority":
            downgrade = {PlanPriority.high: PlanPriority.medium, PlanPriority.medium: PlanPriority.low}
            priority = downgrade.get(plan.priority)
        elif action == "pause":
            from backend.adaptive.models import PlanStatus
            status = PlanStatus.paused

        if not any([intensity, priority, status]):
            return None

        updated = adaptive_store.update_plan(plan_id, status=status, priority=priority, intensity=intensity)
        if updated is None:
            return None

        return {"plan_id": plan_id_str, "action": action, "reason": reason, "applied": True}

    def _apply_difficulty_adjustment(self, user_id: UUID, adj: dict) -> dict | None:
        task_id_str = adj.get("task_id")
        new_diff_str = adj.get("new_difficulty", "")
        reason = adj.get("reason", "")
        if not task_id_str:
            return None

        try:
            task_id = UUID(task_id_str)
            new_diff = TaskDifficulty(new_diff_str)
        except ValueError:
            return None

        task = adaptive_store.get_task(task_id)
        if task is None or task.status == TaskStatus.done or new_diff == task.difficulty:
            return None

        res = adaptive_store.client.table("tasks").update({
            "difficulty": new_diff.value,
        }).eq("id", str(task_id)).execute()
        if not res[1]:
            return None

        adaptive_store.record_event(
            user_id=user_id, task_id=task_id, plan_id=task.plan_id,
            event_type=EventType.rescheduled,
            feedback_text=f"Deep review difficulty: {task.difficulty.value} -> {new_diff.value} ({reason})",
        )

        return {
            "task_id": task_id_str,
            "old_difficulty": task.difficulty.value,
            "new_difficulty": new_diff.value,
            "reason": reason,
            "applied": True,
        }

    def _apply_task_modification(self, user_id: UUID, mod: dict) -> dict | None:
        action = mod.get("action", "")
        plan_id_str = mod.get("plan_id")
        reason = mod.get("reason", "")
        if not plan_id_str:
            return None

        try:
            plan_id = UUID(plan_id_str)
        except ValueError:
            return None

        plan = adaptive_store.get_plan(plan_id)
        if plan is None or plan.user_id != user_id:
            return None

        due_in = max(1, min(int(mod.get("due_in_days", 1)), 14))
        target_date = date.today() + timedelta(days=due_in)

        if action == "reschedule":
            return self._mod_reschedule(user_id, mod, plan_id, target_date, reason)
        elif action == "add":
            return self._mod_add(user_id, mod, plan_id, target_date, reason)
        elif action == "remove":
            return self._mod_remove(user_id, mod, plan_id, reason)
        elif action == "merge":
            return self._mod_merge(user_id, mod, plan_id, reason)
        return None

    def _mod_reschedule(self, user_id: UUID, mod: dict, plan_id: UUID, target_date: date, reason: str) -> dict | None:
        task_id_str = mod.get("task_id")
        if not task_id_str:
            return None
        try:
            task_id = UUID(task_id_str)
        except ValueError:
            return None
        task = adaptive_store.get_task(task_id)
        if task is None or task.status == TaskStatus.done:
            return None
        updated = adaptive_store.reschedule_task(task_id, target_date)
        if updated:
            adaptive_store.record_event(
                user_id=user_id, task_id=task_id, plan_id=plan_id,
                event_type=EventType.rescheduled,
                feedback_text=f"Deep review rescheduled: {reason}",
            )
        return {"action": "reschedule", "task_id": task_id_str, "new_date": target_date.isoformat(), "reason": reason, "applied": True}

    def _mod_add(self, user_id: UUID, mod: dict, plan_id: UUID, target_date: date, reason: str) -> dict | None:
        title = mod.get("title", "").strip()
        if not title:
            return None
        task_data = {
            "title": title,
            "due_date": target_date.isoformat(),
            "status": "pending",
            "priority": mod.get("priority", "medium"),
            "difficulty": mod.get("difficulty", "intermediate"),
            "plan_id": str(plan_id),
        }
        res = adaptive_store.client.table("tasks").insert(task_data).execute()
        if res[1]:
            new_task = adaptive_store._map_task(res[1][0])
            adaptive_store.record_event(
                user_id=user_id, task_id=new_task.id, plan_id=plan_id,
                event_type=EventType.rescheduled,
                feedback_text=f"Deep review added task: {reason}",
            )
            return {"action": "add", "task_id": str(new_task.id), "title": title, "reason": reason, "applied": True}
        return None

    def _mod_remove(self, user_id: UUID, mod: dict, plan_id: UUID, reason: str) -> dict | None:
        task_id_str = mod.get("task_id")
        if not task_id_str:
            return None
        try:
            task_id = UUID(task_id_str)
        except ValueError:
            return None
        task = adaptive_store.get_task(task_id)
        if task is None or task.status == TaskStatus.done:
            return None
        adaptive_store.client.table("tasks").delete().eq("id", str(task_id)).execute()
        adaptive_store.record_event(
            user_id=user_id, task_id=task_id, plan_id=plan_id,
            event_type=EventType.rescheduled,
            feedback_text=f"Deep review removed task: {reason}",
        )
        return {"action": "remove", "task_id": task_id_str, "reason": reason, "applied": True}

    def _mod_merge(self, user_id: UUID, mod: dict, plan_id: UUID, reason: str) -> dict | None:
        task_id_str = mod.get("task_id")
        title = mod.get("title", "").strip()
        if not task_id_str or not title:
            return None
        try:
            task_id = UUID(task_id_str)
        except ValueError:
            return None
        task = adaptive_store.get_task(task_id)
        if task is None:
            return None
        res = adaptive_store.client.table("tasks").update({"title": title}).eq("id", str(task_id)).execute()
        if res[1]:
            adaptive_store.record_event(
                user_id=user_id, task_id=task_id, plan_id=plan_id,
                event_type=EventType.rescheduled,
                feedback_text=f"Deep review merged task: {reason}",
            )
            return {"action": "merge", "task_id": task_id_str, "new_title": title, "reason": reason, "applied": True}
        return None

    # ── Helpers ──────────────────────────────────────────────────────────────

    def _task_snapshot(self, t: TaskRow) -> dict:
        return {
            "id": str(t.id),
            "plan_id": str(t.plan_id),
            "title": t.title,
            "due_date": t.due_date.isoformat() if t.due_date else None,
            "status": t.status.value,
            "difficulty": t.difficulty.value,
            "carry_over_count": t.carry_over_count,
        }

    def _plan_snapshot(self, p: PlanRow, user_id: UUID) -> dict:
        due_tasks = adaptive_store.get_due_tasks(user_id, date.today())
        plan_tasks = [t for t in due_tasks if t.plan_id == p.id]
        return {
            "plan_id": str(p.id),
            "title": p.title,
            "priority": p.priority.value,
            "intensity": p.intensity.value,
            "status": p.status.value,
            "tasks_today": len(plan_tasks),
            "tasks_done": len([t for t in plan_tasks if t.status == TaskStatus.done]),
            "tasks_skipped": len([t for t in plan_tasks if t.status == TaskStatus.skipped]),
        }

    def _fallback_adjustment(self, user_id: UUID, missed: list[dict], partial: list[dict], trigger_reason: str) -> dict:
        """Rule-based fallback if LLM fails."""
        adjustments = {
            "trigger_reason": trigger_reason,
            "plan_adjustments": [],
            "difficulty_adjustments": [],
            "task_modifications": [],
            "summary": "Deep review via fallback rules (LLM unavailable).",
            "llm_raw": None,
        }

        tomorrow = date.today() + timedelta(days=1)
        for t in missed + partial:
            task_id_str = t.get("id")
            if not task_id_str:
                continue
            try:
                task_id = UUID(task_id_str)
            except ValueError:
                continue
            updated = adaptive_store.reduce_task_difficulty(task_id)
            if updated:
                adjustments["difficulty_adjustments"].append({
                    "task_id": task_id_str,
                    "new_difficulty": updated.difficulty.value,
                    "reason": "auto-reduced after skip/partial (fallback)",
                    "applied": True,
                })
            rescheduled = adaptive_store.reschedule_task(task_id, tomorrow)
            if rescheduled:
                adjustments["task_modifications"].append({
                    "action": "reschedule",
                    "task_id": task_id_str,
                    "new_date": tomorrow.isoformat(),
                    "reason": "auto-rescheduled after skip/partial (fallback)",
                    "applied": True,
                })

        return adjustments


deep_review_service = DeepReviewService()
