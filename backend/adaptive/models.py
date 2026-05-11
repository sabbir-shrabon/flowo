"""Database row mappers — one class per table, maps Supabase rows → Python objects."""

from __future__ import annotations

from datetime import date, datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


# ── Enums ──────────────────────────────────────────────────────────────────────

class PlanStatus(str, Enum):
    setup = "setup"
    active = "active"
    paused = "paused"
    completed = "completed"


class PlanPriority(str, Enum):
    high = "high"
    medium = "medium"
    low = "low"


class PlanIntensity(str, Enum):
    light = "light"
    moderate = "moderate"
    intense = "intense"


class TaskStatus(str, Enum):
    pending = "pending"
    done = "done"
    skipped = "skipped"
    partial = "partial"
    rescheduled = "rescheduled"


class SkipType(str, Enum):
    skip_today = "skip_today"
    skip_permanently = "skip_permanently"


class TaskDifficulty(str, Enum):
    easy = "easy"
    intermediate = "intermediate"
    hard = "hard"


class EventType(str, Enum):
    done = "done"
    skipped = "skipped"
    partial = "partial"
    feedback = "feedback"
    rescheduled = "rescheduled"


class MemoryKey(str, Enum):
    goal = "goal"
    constraint = "constraint"
    preference = "preference"
    pattern = "pattern"
    schedule_habit = "schedule_habit"
    deadline = "deadline"
    context = "context"
    milestone = "milestone"


class MilestoneStatus(str, Enum):
    locked = "locked"
    active = "active"
    completed = "completed"


class AdjustmentStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    dismissed = "dismissed"


# ── ORM-style row models ──────────────────────────────────────────────────────

class UserPreferences(BaseModel):
    id: UUID = Field(...)
    user_id: UUID
    max_tasks_per_day: int = 4
    auto_reduce_enabled: bool = True
    reduced_until: date | None = None
    created_at: datetime
    updated_at: datetime


class PlanRow(BaseModel):
    """Full plan row including new adaptive columns."""
    id: UUID = Field(...)
    goal_id: UUID | None = None
    memory_id: UUID | None = None
    user_id: UUID | None = None
    title: str | None = None
    status: PlanStatus = PlanStatus.active
    priority: PlanPriority = PlanPriority.medium
    intensity: PlanIntensity = PlanIntensity.moderate
    duration_days: int | None = None
    schedule_prefs: dict | None = None
    created_at: datetime
    updated_at: datetime


class TaskRow(BaseModel):
    """Full task row including new adaptive columns."""
    id: UUID = Field(...)
    plan_id: UUID
    title: str
    description: str | None = None
    due_date: date | None = None
    status: TaskStatus = TaskStatus.pending
    priority: str = "medium"
    difficulty: TaskDifficulty = TaskDifficulty.intermediate
    parent_id: UUID | None = None
    carry_over_count: int = 0
    milestone_id: UUID | None = None
    order_index: int = 0
    duration_minutes: int | None = None
    detail_json: dict | None = None
    rescheduled_from: date | None = None
    struggling: bool = False
    skip_reason: str | None = None
    skipped_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class MilestoneRow(BaseModel):
    """Full milestone row."""
    id: UUID = Field(...)
    plan_id: UUID
    user_id: UUID
    title: str
    description: str | None = None
    order_index: int = 0
    status: MilestoneStatus = MilestoneStatus.locked
    suggested_days: int | None = None
    outcome: str | None = None
    insight_json: dict | None = None
    created_at: datetime
    updated_at: datetime


class MemoryRow(BaseModel):
    id: UUID = Field(...)
    user_id: UUID
    key: MemoryKey
    value: str
    source: str = "chat_extraction"
    importance: int = 0
    confidence: float = 0.5
    user_visible: bool = True
    goal_id: UUID | None = None
    created_at: datetime
    updated_at: datetime


class EventRow(BaseModel):
    id: UUID = Field(...)
    user_id: UUID
    task_id: UUID
    plan_id: UUID
    event_type: EventType
    feedback_rating: int | None = None
    feedback_text: str | None = None
    created_at: datetime


class AdjustmentSuggestionRow(BaseModel):
    id: UUID = Field(...)
    user_id: UUID
    plan_id: UUID
    reason: str
    suggested_tasks: list[dict] | None = None
    status: AdjustmentStatus = AdjustmentStatus.pending
    created_at: datetime
    resolved_at: datetime | None = None


class DailySummaryRow(BaseModel):
    id: UUID = Field(...)
    user_id: UUID
    date: date
    summary_text: str = ""
    stats_json: dict = {}
    created_at: datetime


class EpisodicMemoryRow(BaseModel):
    id: UUID = Field(...)
    user_id: UUID
    type: str  # episode | pattern | insight
    content: str
    context_json: dict | None = None
    learned_rule: str | None = None
    created_at: datetime


class TaskHistoryRow(BaseModel):
    """Task completion history record - one row per completed task."""
    id: UUID = Field(...)
    user_id: UUID
    task_id: UUID
    task_index: int = 0  # 1-based position in the plan roadmap
    task_name: str  # snapshot at completion time
    milestone_id: UUID | None = None
    milestone_name: str | None = None  # snapshot at completion time
    plan_id: UUID
    plan_name: str  # snapshot at completion time
    plan_completed: bool = False  # true if plan was completed when this task was done
    working_day_index: int | None = None
    calendar_date: date
    completed_at: datetime
    created_at: datetime
