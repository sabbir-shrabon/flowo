"""Focused API tests for task subtasks.

Run:
    py -m unittest backend.adaptive.tests.test_subtasks_api
"""

from __future__ import annotations

import unittest
from datetime import date, datetime, timezone
from uuid import UUID, uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.adaptive.models import (
    PlanIntensity,
    PlanPriority,
    PlanRow,
    PlanStatus,
    SubtaskRow,
    TaskDifficulty,
    TaskRow,
    TaskStatus,
)
from backend.adaptive.routes import router as router_module
from backend.auth import get_current_user


class _FakeStore:
    def __init__(self):
        self.user_id = uuid4()
        self.plan = PlanRow(
            id=uuid4(),
            user_id=self.user_id,
            title="Backend Test Plan",
            status=PlanStatus.active,
            priority=PlanPriority.medium,
            intensity=PlanIntensity.moderate,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        self.task = TaskRow(
            id=uuid4(),
            plan_id=self.plan.id,
            title="Parent task",
            description="Use this task for subtask tests",
            due_date=date.today(),
            status=TaskStatus.pending,
            priority="medium",
            difficulty=TaskDifficulty.intermediate,
            order_index=0,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        self.subtasks: dict[UUID, SubtaskRow] = {}
        self.deleted_task_ids: set[UUID] = set()

    def get_task(self, task_id):
        if task_id in self.deleted_task_ids:
            return None
        return self.task if task_id == self.task.id else None

    def get_plan(self, plan_id):
        return self.plan if plan_id == self.plan.id else None

    def get_milestones_for_plan(self, _user_id, _plan_id):
        return []

    def list_subtasks_by_task(self, task_id):
        rows = [s for s in self.subtasks.values() if s.task_id == task_id]
        return sorted(rows, key=lambda s: (s.completed, s.order_index, s.created_at))

    def next_subtask_order_index(self, task_id):
        rows = self.list_subtasks_by_task(task_id)
        return max((s.order_index for s in rows), default=-1) + 1

    def create_subtask(self, task_id, title, order_index):
        row = SubtaskRow(
            id=uuid4(),
            task_id=task_id,
            title=title,
            completed=False,
            order_index=order_index,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        self.subtasks[row.id] = row
        return row

    def get_subtask(self, subtask_id):
        return self.subtasks.get(subtask_id)

    def update_subtask(self, subtask_id, title=None, completed=None, order_index=None):
        row = self.subtasks.get(subtask_id)
        if row is None:
            return None
        updated = row.model_copy(
            update={
                "title": title if title is not None else row.title,
                "completed": completed if completed is not None else row.completed,
                "order_index": order_index if order_index is not None else row.order_index,
                "updated_at": datetime.now(timezone.utc),
            }
        )
        self.subtasks[subtask_id] = updated
        return updated

    def delete_subtask(self, subtask_id):
        return self.subtasks.pop(subtask_id, None) is not None

    def count_subtasks_by_task(self, task_id):
        rows = self.list_subtasks_by_task(task_id)
        return {
            "total": len(rows),
            "completed": sum(1 for row in rows if row.completed),
        }

    def all_subtasks_completed(self, task_id):
        counts = self.count_subtasks_by_task(task_id)
        return counts["total"] > 0 and counts["total"] == counts["completed"]

    def cascade_delete_task(self, task_id):
        self.deleted_task_ids.add(task_id)
        for subtask_id, subtask in list(self.subtasks.items()):
            if subtask.task_id == task_id:
                del self.subtasks[subtask_id]


class SubtaskApiTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.store = _FakeStore()
        self.original_store = router_module.adaptive_store
        self.original_chat = router_module.chatResponse
        self.original_complete = router_module._complete_task_status_flow
        router_module.adaptive_store = self.store

        app = FastAPI()
        app.dependency_overrides[get_current_user] = lambda: self.store.user_id
        app.include_router(router_module.router)
        self.client = TestClient(app, raise_server_exceptions=False)

    def tearDown(self):
        router_module.adaptive_store = self.original_store
        router_module.chatResponse = self.original_chat
        router_module._complete_task_status_flow = self.original_complete

    def test_crud_orders_unchecked_before_checked(self):
        task_id = str(self.store.task.id)
        first = self.client.post(f"/api/adaptive/tasks/{task_id}/subtasks", json={"title": "First"}).json()
        second = self.client.post(f"/api/adaptive/tasks/{task_id}/subtasks", json={"title": "Second"}).json()

        self.assertEqual(first["order_index"], 0)
        self.assertEqual(second["order_index"], 1)

        patch = self.client.patch(
            f"/api/adaptive/subtasks/{first['id']}",
            json={"completed": True, "title": "First done"},
        )
        self.assertEqual(patch.status_code, 200)

        listed = self.client.get(f"/api/adaptive/tasks/{task_id}/subtasks").json()
        self.assertEqual([row["title"] for row in listed], ["Second", "First done"])

        delete = self.client.delete(f"/api/adaptive/subtasks/{second['id']}")
        self.assertEqual(delete.status_code, 200)
        self.assertEqual(len(self.store.subtasks), 1)

    def test_generate_endpoint_validates_mock_ai(self):
        router_module.chatResponse = lambda _prompt: """
        {"suggestions":[
          {"title":"Clarify the target outcome"},
          {"title":"Gather the source material"},
          {"title":"Draft the first pass"},
          {"title":"Review and revise"}
        ]}
        """

        res = self.client.post(f"/api/adaptive/tasks/{self.store.task.id}/subtasks/generate")

        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(len(body["suggestions"]), 4)
        self.assertEqual(body["suggestions"][0]["title"], "Clarify the target outcome")

    def test_parent_completion_failure_rolls_back_subtask_toggle(self):
        created = self.store.create_subtask(self.store.task.id, "Only step", 0)

        async def fail_complete(*_args, **_kwargs):
            raise RuntimeError("parent completion failed")

        router_module._complete_task_status_flow = fail_complete
        res = self.client.patch(
            f"/api/adaptive/subtasks/{created.id}",
            json={"completed": True},
        )

        self.assertEqual(res.status_code, 500)
        self.assertFalse(self.store.get_subtask(created.id).completed)

    def test_cascade_delete_removes_subtasks(self):
        self.store.create_subtask(self.store.task.id, "One", 0)
        self.store.create_subtask(self.store.task.id, "Two", 1)

        self.store.cascade_delete_task(self.store.task.id)

        self.assertEqual(self.store.list_subtasks_by_task(self.store.task.id), [])


if __name__ == "__main__":
    unittest.main()
