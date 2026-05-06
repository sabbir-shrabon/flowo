"""Plan Generator — creates a plan + initial tasks from a memory entry via LLM."""

from __future__ import annotations

import json
from datetime import date, timedelta
from uuid import UUID

from backend.adaptive.db import adaptive_store
from backend.adaptive.models import (
    MemoryKey,
    MilestoneStatus,
    PlanIntensity,
    PlanPriority,
    TaskDifficulty,
)
from backend.lib.llm import chatResponse


PLAN_GENERATION_PROMPT = """You are a planning engine. Given a user's goal, preferences, constraints, and difficulty level, create a milestone-structured plan.

Break the plan into 2–5 milestones, each with 2–4 tasks. The first milestone should be achievable within days; later milestones build on earlier ones.

Return EXACTLY a JSON object with these keys:
- "plan_title": string — concise plan title
- "plan_summary": string — 1-2 sentence overview of the plan
- "duration_weeks": number — estimated total weeks to complete
- "milestones": array of objects, each with:
    - "title": string
    - "description": string — what this milestone achieves
    - "order_index": number (0-based)
    - "tasks": array of objects, each with:
        - "title": string
        - "description": string — brief description of the task
        - "duration_minutes": number — estimated time in minutes
        - "order_index": number (0-based within milestone)
        - "scheduled_date": "YYYY-MM-DD" or null — suggested date, starting from today

Do not include any markdown blocks, only the raw JSON.

Goal: {goal}
Preferences: {preferences}
Constraints: {constraints}
Difficulty level: {difficulty}
Today's date: {today}"""


class PlanGeneratorService:
    """Generates a plan with initial tasks from structured memory data."""

    def create_plan_from_memory(self, user_id: UUID, memory_id: UUID) -> dict:
        """
        1. Load the goal memory entry + related memory (preferences, constraints, difficulty)
        2. Call LLM once to generate milestone-structured plan
        3. Store plan, milestones, and tasks in DB
        4. Return the created plan with milestones and tasks nested
        """
        # Load the source memory entry
        goal_memory = adaptive_store.get_memory(memory_id)
        if goal_memory is None:
            return {"error": "Memory entry not found"}
        if goal_memory.user_id != user_id:
            return {"error": "Memory entry does not belong to user"}

        # Gather all related memory for this user
        all_memory = adaptive_store.list_memory(user_id)
        memory_by_key: dict[str, str] = {}
        for m in all_memory:
            memory_by_key[m.key.value] = m.value

        goal = memory_by_key.get("goal", goal_memory.value)
        preferences = memory_by_key.get("preference", "none specified")
        constraints = memory_by_key.get("constraint", "none specified")
        difficulty = memory_by_key.get("context", "beginner")

        prompt = PLAN_GENERATION_PROMPT.format(
            goal=goal,
            preferences=preferences,
            constraints=constraints,
            difficulty=difficulty,
            today=date.today().isoformat(),
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
            print(f"Plan generator LLM failed: {exc}")
            return self._fallback_plan(user_id, goal_memory)

        # Validate milestone structure
        milestones_data = parsed.get("milestones", [])
        if not milestones_data:
            return self._fallback_plan(user_id, goal_memory)

        # Extract plan-level fields
        title = parsed.get("plan_title", goal_memory.value[:60])
        priority = self._parse_priority(parsed.get("priority", "medium"))
        intensity = self._parse_intensity(parsed.get("intensity", "moderate"))
        goal_id = goal_memory.goal_id

        # 1. Create the plan record
        plan, _ = adaptive_store.create_plan_with_tasks(
            user_id=user_id,
            goal_id=goal_id,
            title=title,
            priority=priority,
            intensity=intensity,
            tasks=[],  # tasks inserted separately per milestone below
        )

        # 2. For each milestone, create milestone record + its tasks
        result_milestones = []
        for ms_idx, ms_data in enumerate(milestones_data):
            ms_status = MilestoneStatus.active
            milestone = adaptive_store.create_milestone(
                user_id=user_id,
                plan_id=plan.id,
                data={
                    "title": ms_data.get("title", f"Milestone {ms_idx + 1}"),
                    "description": ms_data.get("description", ""),
                    "order_index": ms_data.get("order_index", ms_idx),
                    "status": ms_status,
                },
            )

            # 3. Create task records linked to plan + milestone
            ms_tasks_data = ms_data.get("tasks", [])
            tasks_to_insert = []
            for t_data in ms_tasks_data:
                scheduled = t_data.get("scheduled_date")
                due_date = scheduled if scheduled else None
                tasks_to_insert.append({
                    "plan_id": str(plan.id),
                    "milestone_id": str(milestone.id),
                    "title": t_data.get("title", "Untitled task"),
                    "description": t_data.get("description", ""),
                    "due_date": due_date,
                    "duration_minutes": t_data.get("duration_minutes", 30),
                    "order_index": t_data.get("order_index", 0),
                    "status": "pending",
                    "priority": "medium",
                    "difficulty": "intermediate",
                })

            task_rows = []
            if tasks_to_insert:
                task_res = adaptive_store.client.table("tasks").insert(tasks_to_insert).execute()
                if task_res[1]:
                    task_rows = [adaptive_store._map_task(row) for row in task_res[1]]

            result_milestones.append({
                "milestone": milestone,
                "tasks": task_rows,
            })

        return {"plan": plan, "milestones": result_milestones}

    def _fallback_plan(self, user_id: UUID, goal_memory) -> dict:
        """Rule-based fallback when LLM fails — produces a simple milestone-structured plan."""
        title = goal_memory.value[:60]
        if len(goal_memory.value) > 60:
            title = title.rstrip() + "..."

        plan, _ = adaptive_store.create_plan_with_tasks(
            user_id=user_id,
            goal_id=goal_memory.goal_id,
            title=title,
            priority=PlanPriority.medium,
            intensity=PlanIntensity.moderate,
            tasks=[],
        )

        fallback_milestones = [
            {
                "title": "Getting Started",
                "description": "Research and set up your learning environment",
                "tasks": [
                    {"title": "Research and define success criteria", "due_date": (date.today() + timedelta(days=1)).isoformat(), "duration_minutes": 30, "order_index": 0},
                    {"title": "Gather resources and set up environment", "due_date": (date.today() + timedelta(days=2)).isoformat(), "duration_minutes": 45, "order_index": 1},
                ],
            },
            {
                "title": "First Practice",
                "description": "Complete your first practice sessions",
                "tasks": [
                    {"title": "Complete first practice session and take notes", "due_date": (date.today() + timedelta(days=3)).isoformat(), "duration_minutes": 60, "order_index": 0},
                    {"title": "Apply what you learned in a small exercise", "due_date": (date.today() + timedelta(days=4)).isoformat(), "duration_minutes": 60, "order_index": 1},
                ],
            },
            {
                "title": "Review & Next Steps",
                "description": "Review progress and plan ahead",
                "tasks": [
                    {"title": "Review progress and plan the next week", "due_date": (date.today() + timedelta(days=5)).isoformat(), "duration_minutes": 30, "order_index": 0},
                ],
            },
        ]

        result_milestones = []
        for ms_idx, ms in enumerate(fallback_milestones):
            ms_status = MilestoneStatus.active
            milestone = adaptive_store.create_milestone(
                user_id=user_id,
                plan_id=plan.id,
                data={
                    "title": ms["title"],
                    "description": ms["description"],
                    "order_index": ms_idx,
                    "status": ms_status,
                },
            )

            tasks_to_insert = []
            for t in ms["tasks"]:
                tasks_to_insert.append({
                    "plan_id": str(plan.id),
                    "milestone_id": str(milestone.id),
                    "title": t["title"],
                    "due_date": t["due_date"],
                    "duration_minutes": t["duration_minutes"],
                    "order_index": t["order_index"],
                    "status": "pending",
                    "priority": "medium",
                    "difficulty": "intermediate",
                })

            task_rows = []
            if tasks_to_insert:
                task_res = adaptive_store.client.table("tasks").insert(tasks_to_insert).execute()
                if task_res[1]:
                    task_rows = [adaptive_store._map_task(row) for row in task_res[1]]

            result_milestones.append({
                "milestone": milestone,
                "tasks": task_rows,
            })

        return {"plan": plan, "milestones": result_milestones}

    def _parse_priority(self, val: str) -> PlanPriority:
        try:
            return PlanPriority(val)
        except ValueError:
            return PlanPriority.medium

    def _parse_intensity(self, val: str) -> PlanIntensity:
        try:
            return PlanIntensity(val)
        except ValueError:
            return PlanIntensity.moderate


plan_generator_service = PlanGeneratorService()
