"""Task Detail Generator — lazily generates rich detail for a task via LLM."""

from __future__ import annotations

import json
from uuid import UUID

from backend.lib.llm import chatResponse


TASK_DETAIL_PROMPT = """You are a task detail generator. Given a task title, its parent plan context, and the user's memory (goals, preferences, constraints), generate rich detail to help the user understand and complete this task.

Return EXACTLY a JSON object with these keys:
- "what_is_this": string — 2-3 sentence explanation of what this task is
- "why_it_matters": string — 1-2 sentences on why this task is in the plan
- "how_to_do_it": array of objects, each with:
    - "step": integer (1-based)
    - "instruction": string
- "resources": array of objects, each with:
    - "type": "video" | "article" | "app" | "book"
    - "title": string
    - "description": string
- "todays_example": string — a concrete example they can do right now
- "expert_tip": string — one concise expert tip or shortcut for this task (must not be empty)
- "estimated_difficulty": "easy" | "medium" | "hard"

Do not include any markdown blocks, only the raw JSON.

Task title: {task_title}
Plan context: {plan_context}
User memory: {user_memory}"""


class TaskDetailGeneratorService:
    """Generates rich task detail on demand (lazy generation) and caches it."""

    def generate_task_detail(
        self,
        task_id: UUID,
        task_title: str,
        plan_context: str,
        user_memory: dict,
        system: str | None = None,
    ) -> dict:
        """
        Call the LLM to generate rich detail for a task.
        Returns the parsed JSON detail dict.
        """
        prompt = TASK_DETAIL_PROMPT.format(
            task_title=task_title,
            plan_context=plan_context or "No plan context available",
            user_memory=json.dumps(user_memory) if user_memory else "No user memory available",
        )

        try:
            content = chatResponse(prompt, system=system)
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
            print(f"Task detail generator LLM failed: {exc}")
            return self._fallback_detail(task_title)

        # Validate expected keys exist
        required_keys = {"what_is_this", "why_it_matters", "how_to_do_it", "resources", "todays_example", "expert_tip", "estimated_difficulty"}
        if not required_keys.issubset(parsed.keys()):
            print(f"Task detail generator: LLM response missing keys. Got: {list(parsed.keys())}")
            return self._fallback_detail(task_title)

        return parsed

    def _fallback_detail(self, task_title: str) -> dict:
        """Rule-based fallback when LLM fails."""
        return {
            "what_is_this": f"This task involves working on '{task_title}'. It is part of your learning plan and is designed to help you make progress toward your goal.",
            "why_it_matters": "Each task in your plan builds on the previous ones, helping you develop skills incrementally.",
            "how_to_do_it": [
                {"step": 1, "instruction": f"Review what '{task_title}' means in the context of your goal"},
                {"step": 2, "instruction": "Break it down into smaller sub-steps you can complete today"},
                {"step": 3, "instruction": "Set a timer and work on the first sub-step for 15-25 minutes"},
            ],
            "resources": [
                {"type": "article", "title": "Getting Started Guide", "description": "A general guide on how to approach new learning tasks"},
            ],
            "todays_example": f"Spend 15 minutes researching '{task_title}' and write down 3 key things you learned.",
            "expert_tip": "Break the task into the smallest possible first step, then focus only on that. Momentum beats perfectionism.",
            "estimated_difficulty": "medium",
        }


task_detail_generator_service = TaskDetailGeneratorService()
