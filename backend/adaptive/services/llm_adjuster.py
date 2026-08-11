"""LLM Adjuster — suggests plan adjustments using LLM. Never auto-applies."""

from __future__ import annotations

import json
from datetime import date, timedelta
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import AdjustmentStatus, TaskStatus
from backend.lib.llm_client import send_chat


class LLMAdjusterService:
    """Uses LLM to generate task suggestions for flagged plans. Requires user approval."""

    def generate_suggestions(self, suggestion_id: UUID) -> list[dict] | None:
        """
        Given a pending adjustment suggestion, use LLM to propose revised tasks.
        Returns the suggested task list or None on failure.
        Does NOT modify the plan — only fills in the suggestion's suggested_tasks.
        """
        suggestion = adaptive_store.get_suggestion(suggestion_id)
        if suggestion is None or suggestion.status != AdjustmentStatus.pending:
            return None

        plan = adaptive_store.get_plan(suggestion.plan_id)
        if plan is None:
            return None

        # Gather context: existing tasks + recent events
        due_tasks = adaptive_store.get_due_tasks(plan.user_id, date.today())
        recent_events = adaptive_store.get_events_for_user(
            plan.user_id, since=None,
        )[-20:]  # last 20 events for context

        prompt = (
            "You are an adaptive planning assistant. "
            "A plan needs adjustment based on user behavior.\n\n"
            "Return EXACTLY a JSON dictionary with a 'tasks' key mapping to a list of tasks. "
            "Each task must have 'title' (string), 'due_in_days' (integer, 1 to 365), "
            "and 'priority' ('high', 'medium', 'low').\n"
            "Do not include any raw markdown blocks, only the JSON object.\n\n"
            f"Plan title: {plan.title or plan.id}\n"
            f"Adjustment reason: {suggestion.reason}\n"
            f"Today's date: {date.today().isoformat()}\n"
            f"Current due tasks: {json.dumps([self._task_snapshot(t) for t in due_tasks[:8]])}\n"
            f"Recent events: {json.dumps([self._event_snapshot(e) for e in recent_events[:10]])}\n"
        )

        try:
            messages = [{"role": "user", "content": prompt}]
            content = send_chat(str(plan.user_id), messages)
            content = content.strip()
            if content.startswith("```json"):
                content = content[7:]
            if content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()

            parsed = json.loads(content)
            tasks = []
            for item in parsed.get("tasks", []):
                tasks.append({
                    "title": item["title"],
                    "due_date": (date.today() + timedelta(days=int(item["due_in_days"]))).isoformat(),
                    "priority": item.get("priority", "medium"),
                    "status": "pending",
                })
            if len(tasks) < 2:
                return None
            return tasks
        except Exception as exc:
            print(f"LLM Adjuster failed: {exc}")
            return None

    def apply_approved_suggestion(self, suggestion_id: UUID) -> bool:
        """
        Apply an approved suggestion — replace pending tasks in the plan.
        Only called after user explicitly approves.
        """
        suggestion = adaptive_store.get_suggestion(suggestion_id)
        if suggestion is None or suggestion.status != AdjustmentStatus.pending:
            return False

        if not suggestion.suggested_tasks:
            return False

        # Mark suggestion as approved
        adaptive_store.resolve_suggestion(suggestion_id, AdjustmentStatus.approved)

        # Replace pending tasks in the plan with suggested ones
        # Delete existing pending/partial tasks for this plan
        pending_res = (
            adaptive_store.client.table("tasks")
            .select("id")
            .eq("plan_id", str(suggestion.plan_id))
            .in_("status", ["pending", "partial"])
            .execute()
        )
        for row in pending_res[1]:
            adaptive_store.client.table("tasks").delete().eq("id", row["id"]).execute()

        # Insert the suggested tasks
        tasks_to_insert = [
            {
                "plan_id": str(suggestion.plan_id),
                "title": t["title"],
                "due_date": t.get("due_date"),
                "status": "pending",
                "priority": t.get("priority", "medium"),
            }
            for t in suggestion.suggested_tasks
        ]
        if tasks_to_insert:
            adaptive_store.client.table("tasks").insert(tasks_to_insert).execute()
        return True

    def _task_snapshot(self, task) -> dict:
        return {
            "title": task.title,
            "due_date": task.due_date.isoformat() if task.due_date else None,
            "status": task.status.value,
            "priority": task.priority,
            "carry_over_count": task.carry_over_count,
        }

    def _event_snapshot(self, event) -> dict:
        return {
            "event_type": event.event_type.value,
            "feedback_rating": event.feedback_rating,
            "created_at": event.created_at.isoformat(),
        }


llm_adjuster_service = LLMAdjusterService()
