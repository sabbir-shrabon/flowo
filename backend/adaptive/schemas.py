"""Pydantic schemas — request/response models for the API layer."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from backend.adaptive.models import (
    AdjustmentStatus,
    EventType,
    MemoryKey,
    MilestoneStatus,
    PlanIntensity,
    PlanPriority,
    PlanStatus,
    SkipType,
    TaskDifficulty,
    TaskStatus,
)


# ── User Preferences ──────────────────────────────────────────────────────────

class UserPreferencesResponse(BaseModel):
    user_id: UUID
    max_tasks_per_day: int
    auto_reduce_enabled: bool = True
    reduced_until: date | None = None
    created_at: datetime
    updated_at: datetime


class UserPreferencesUpdate(BaseModel):
    max_tasks_per_day: int = Field(..., ge=1, le=10)


# ── Plans ──────────────────────────────────────────────────────────────────────

class PlanResponse(BaseModel):
    id: UUID
    goal_id: UUID | None = None
    memory_id: UUID | None = None
    user_id: UUID | None = None
    title: str | None = None
    status: PlanStatus
    priority: PlanPriority
    intensity: PlanIntensity
    duration_days: int | None = None
    schedule_prefs: dict | None = None
    progress_pct: float = 0.0
    total_tasks: int = 0
    remaining_tasks: int = 0
    created_at: datetime
    updated_at: datetime


class PlanUpdateRequest(BaseModel):
    title: str | None = None
    status: PlanStatus | None = None
    priority: PlanPriority | None = None
    intensity: PlanIntensity | None = None


class AdaptPlanRequest(BaseModel):
    duration_days: int = Field(..., ge=1, le=365, description="Number of days to complete the plan")
    working_days: list[int] = Field(
        ..., min_length=1, max_length=7,
        description="Working days as integers 0=Mon … 6=Sun",
    )


class PlanControlRequest(BaseModel):
    plan_id: UUID


# ── Tasks ──────────────────────────────────────────────────────────────────────

class TaskResponse(BaseModel):
    id: UUID
    plan_id: UUID
    title: str
    description: str | None = None
    due_date: date | None = None
    status: TaskStatus
    priority: str
    difficulty: TaskDifficulty
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


class TaskCreateRequest(BaseModel):
    title: str
    due_date: date | None = None
    priority: str = "medium"
    parent_id: UUID | None = None


class TaskUpdateRequest(BaseModel):
    task_id: UUID
    status: TaskStatus = Field(..., description="New status: done, skipped, or partial")
    feedback_text: str | None = None


class PullExtraTasksRequest(BaseModel):
    count: int = Field(..., ge=1, le=3)


class DailyPlanMetadata(BaseModel):
    id: UUID
    title: str | None = None
    priority: PlanPriority | None = None
    status: PlanStatus | None = None


class DailyMilestoneMetadata(BaseModel):
    id: UUID
    plan_id: UUID
    title: str
    status: MilestoneStatus
    order_index: int = 0


# ── Memory ─────────────────────────────────────────────────────────────────────

class MemoryResponse(BaseModel):
    id: UUID
    user_id: UUID
    key: MemoryKey
    value: str
    source: str
    importance: int = 0
    confidence: float = 0.5
    user_visible: bool = True
    goal_id: UUID | None = None
    created_at: datetime
    updated_at: datetime


class MemoryCreateRequest(BaseModel):
    key: MemoryKey
    value: str = Field(..., min_length=1)
    source: str = "chat_extraction"
    importance: int = 0
    confidence: float = 0.5
    user_visible: bool = True
    goal_id: UUID | None = None


# ── Events ──────────────────────────────────────────────────────────────────────

class EventResponse(BaseModel):
    id: UUID
    user_id: UUID
    task_id: UUID
    plan_id: UUID
    event_type: EventType
    feedback_rating: int | None = None
    feedback_text: str | None = None
    created_at: datetime


class EventCreateRequest(BaseModel):
    task_id: UUID
    plan_id: UUID
    event_type: EventType
    feedback_rating: int | None = Field(None, ge=1, le=5)
    feedback_text: str | None = None


# ── Skip / Feedback shortcuts ─────────────────────────────────────────────────

class SkipRequest(BaseModel):
    skip_type: SkipType = SkipType.skip_today
    feedback_text: str | None = None


class FeedbackRequest(BaseModel):
    feedback_rating: int = Field(..., ge=1, le=5)
    feedback_text: str | None = None


# ── Scheduler ──────────────────────────────────────────────────────────────────

class DailyTasksResponse(BaseModel):
    date: date
    tasks: list[TaskResponse]
    total_available: int
    selected_count: int
    max_tasks_per_day: int
    selected_task_ids: list[UUID] = Field(default_factory=list)
    plans_metadata: dict[str, DailyPlanMetadata] = Field(default_factory=dict)
    milestones_metadata: dict[str, DailyMilestoneMetadata] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)


# ── Milestones ─────────────────────────────────────────────────────────────────

class MilestoneCreate(BaseModel):
    title: str = Field(..., min_length=1)
    description: str | None = None
    order_index: int = 0


class MilestoneUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    status: MilestoneStatus | None = None


class MilestoneResponse(BaseModel):
    id: UUID
    plan_id: UUID
    user_id: UUID
    title: str
    description: str | None = None
    order_index: int = 0
    status: MilestoneStatus
    suggested_days: int | None = None
    outcome: str | None = None
    tasks: list[TaskResponse] = []
    created_at: datetime
    updated_at: datetime


class MilestoneInsightResponse(BaseModel):
    milestone_id: UUID
    insight: dict[str, Any]
    raw: str | None = None
    generated: bool = True


# ── Adjustment Suggestions ─────────────────────────────────────────────────────

class AdjustmentSuggestionResponse(BaseModel):
    id: UUID
    plan_id: UUID
    reason: str
    suggested_tasks: list[dict]
    status: AdjustmentStatus
    created_at: datetime
    resolved_at: datetime | None = None


class AdjustmentActionRequest(BaseModel):
    """Used for both approve and dismiss — empty body, action is in the URL."""
    pass


# ── Memory Extraction ──────────────────────────────────────────────────────────

class ExtractMemoryRequest(BaseModel):
    conversation: str = Field(..., min_length=10)


class ExtractedField(BaseModel):
    key: str                              # "goal", "preference", "constraint", "context"
    value: str
    id: str | None = None


class ExtractMemoryResponse(BaseModel):
    extracted: list[ExtractedField]
    count: int


# ── Create Plan from Memory ────────────────────────────────────────────────────

class CreatePlanRequest(BaseModel):
    memory_id: UUID = Field(..., description="ID of the goal memory entry to create a plan from")


class GenerateFromAnswersRequest(BaseModel):
    learning_goal: str = Field(..., min_length=1, description="Q1: Main learning goal category (e.g. 'Get a Job')")
    focus_area: str = Field(..., min_length=1, description="Q2: Role/field and what to focus on in detail")
    skill_level: str = Field(..., min_length=1, description="Q3: Current skill level (Beginner / Intermediate / Advanced)")
    focus_or_avoid: str = Field(default="", description="Q4: Specific things to focus on or avoid")
    extra_context: str = Field(default="", description="Q5: Anything else about goals")


class MissingField(BaseModel):
    field: str = Field(..., description="Field name that is missing (e.g. 'learning_goal')")
    question: str = Field(..., description="Question to ask the user to fill this field")


# ── Phase 1: Extract fields from chat ────────────────────────────────────────

class ExtractFromChatRequest(BaseModel):
    """Only the text of the user's own messages — assistant turns are excluded."""
    user_messages: list[str] = Field(..., min_length=1)


class ExtractFromChatResponse(BaseModel):
    """What the LLM could extract and which wizard fields are still missing."""
    extracted: dict[str, str | None] = Field(
        default_factory=dict,
        description="Extracted field values keyed by field name; None means not found",
    )
    missing_fields: list[MissingField] = Field(default_factory=list)
    ready: bool = Field(
        ..., description="True when all 3 required fields are present"
    )


# ── Phase 2: Generate plan from pre-filled wizard fields ──────────────────────

class GenerateFromChatRequest(BaseModel):
    """All 5 wizard fields, fully filled in (mirrors GenerateFromAnswersRequest)."""
    learning_goal: str = Field(..., min_length=1)
    focus_area: str = Field(..., min_length=1)
    skill_level: str = Field(..., min_length=1)
    focus_or_avoid: str = Field(default="")
    extra_context: str = Field(default="")


class GenerateFromChatResponse(BaseModel):
    ready: bool = Field(..., description="True if all fields extracted, False if more info needed")
    missing_fields: list[MissingField] = Field(default_factory=list)
    message: str = Field(default="", description="Message to show the user (questions or confirmation)")
    plan: PlanResponse | None = None
    milestones: list[MilestoneResponse] = Field(default_factory=list)
    task_count: int = 0


class CreatePlanResponse(BaseModel):
    plan: PlanResponse
    milestones: list[MilestoneResponse]
    task_count: int


class TaskDetailResponse(BaseModel):
    task_id: UUID
    detail: dict
    generated: bool


# ── Plan Detail ──────────────────────────────────────────────────────────────────

class PlanDetailStats(BaseModel):
    total_tasks: int = 0
    completed_tasks: int = 0
    remaining_tasks: int = 0
    total_milestones: int = 0
    completed_milestones: int = 0
    progress_pct: int = 0
    current_milestone: dict | None = None
    next_milestone: dict | None = None
    next_task: dict | None = None


class PlanDetailResponse(BaseModel):
    plan: PlanResponse
    stats: PlanDetailStats
    milestones: list[MilestoneResponse]


# ── Plan Chat ────────────────────────────────────────────────────────────────────

class PlanChatRequest(BaseModel):
    message: str = Field(..., min_length=1)
    task_id: str | None = None


class PlanChatAction(BaseModel):
    action: str  # e.g. "reframe_milestone", "rename_milestone", "add_task", "skip_task", etc.
    target_id: str | None = None
    params: dict = {}


class PlanChatResponse(BaseModel):
    reply: str
    actions: list[PlanChatAction] = []


# ── Today Chat ────────────────────────────────────────────────────────────────────

class TodayChatRequest(BaseModel):
    message: str = Field(..., min_length=1)
    task_id: str | None = None


# ── Daily Summary ────────────────────────────────────────────────────────────────

class DailySummaryResponse(BaseModel):
    id: UUID
    user_id: UUID
    date: date
    summary_text: str
    stats_json: dict
    created_at: datetime


# ── Episodic Memory ────────────────────────────────────────────────────────────

class EpisodicMemoryResponse(BaseModel):
    id: UUID
    user_id: UUID
    type: str
    content: str
    context_json: dict | None = None
    learned_rule: str | None = None
    created_at: datetime


# ── Task History ────────────────────────────────────────────────────────────────

class TaskHistoryResponse(BaseModel):
    id: UUID
    user_id: UUID
    task_id: UUID
    task_name: str
    milestone_id: UUID | None = None
    milestone_name: str | None = None
    plan_id: UUID
    plan_name: str
    plan_completed: bool = False
    working_day_index: int | None = None
    calendar_date: date
    completed_at: datetime
    created_at: datetime


class TaskHistoryListResponse(BaseModel):
    """Grouped task history response for the history screen."""
    history: list[TaskHistoryResponse]
    total: int


