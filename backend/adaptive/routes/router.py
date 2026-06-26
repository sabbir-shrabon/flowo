"""Adaptive planning API routes — scheduler, events, preferences, adjustments."""

from __future__ import annotations

from datetime import date
import json
import logging
import re
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
try:
    from slowapi import Limiter
    from slowapi.util import get_remote_address
except ImportError:
    Limiter = None
    get_remote_address = None

logger = logging.getLogger(__name__)

# Rate limiter for expensive operations
if Limiter and get_remote_address:
    limiter = Limiter(key_func=get_remote_address)
    limit_10_per_minute = limiter.limit("10/minute")
else:
    limiter = None

    def limit_10_per_minute(func):
        return func

from backend.auth import get_current_user
from backend.adaptive.db import adaptive_store
from backend.adaptive.models import AdjustmentStatus, EventType, MemoryKey, MilestoneStatus, PlanPriority, PlanStatus, SkipType, TaskStatus
from backend.adaptive.schemas import (
    AdaptPlanRequest,
    AdjustmentActionRequest,
    AdjustmentSuggestionResponse,
    CreatePlanRequest,
    CreatePlanResponse,
    DailyMilestoneMetadata,
    DailyPlanMetadata,
    GenerateFromAnswersRequest,
    GenerateFromChatRequest,
    GenerateFromChatResponse,
    GenerateSubtasksResponse,
    MissingField,
    DailyTasksResponse,
    EventCreateRequest,
    EventResponse,
    ExtractFromChatRequest,
    ExtractFromChatResponse,
    ExtractMemoryRequest,
    ExtractMemoryResponse,
    FeedbackRequest,
    MemoryCreateRequest,
    MemoryResponse,
    MilestoneCreate,
    MilestoneInsightResponse,
    MilestoneResponse,
    MilestoneUpdate,
    PlanChatRequest,
    PlanChatResponse,
    PlanChatAction,
    PullExtraTasksRequest,
    TodayChatRequest,
    PlanControlRequest,
    PlanDetailResponse,
    PlanDetailStats,
    PlanResponse,
    DailySummaryResponse,
    EpisodicMemoryResponse,
    PlanUpdateRequest,
    SkipRequest,
    SubtaskCountsResponse,
    SubtaskCreateRequest,
    SubtaskResponse,
    SubtaskSuggestion,
    SubtaskUpdateRequest,
    TaskDetailResponse,
    TaskHistoryListResponse,
    TaskHistoryResponse,
    TaskResponse,
    TaskUpdateRequest,
    UserPreferencesResponse,
    UserPreferencesUpdate,
)
from backend.adaptive.services.adjuster import adjuster_service
from backend.adaptive.services.deep_review import deep_review_service
from backend.adaptive.services.adaptation_rules import get_next_working_day
from backend.adaptive.services.event_triggers import run_all_triggers
from backend.adaptive.services.task_observer import on_task_status_changed, on_task_skipped, on_app_open
from backend.adaptive.services.events import events_service
from backend.adaptive.services.llm_adjuster import llm_adjuster_service
from backend.adaptive.services.memory_extractor import extract_and_save
from backend.adaptive.services.plan_generator import plan_generator_service
from backend.adaptive.services.task_generator import generate_for_milestone
from backend.adaptive.services.scheduler import scheduler_service
from backend.adaptive.services.task_detail_generator import task_detail_generator_service
from backend.adaptive.services.context_builder import build as build_context
from backend.lib.llm import LLMProviderError, chatResponse

router = APIRouter(prefix="/api/adaptive", tags=["adaptive"])

# ── Server-side V2 Feature Flag ───────────────────────────────────────────────
# Can be flipped via the rollback-webhook endpoint to disable V2 endpoints.
_v2_enabled: bool = True


MILESTONE_INSIGHT_PROMPT = """You are a planning assistant. Given a milestone and its tasks, generate structured insight to help the user succeed.

Return EXACTLY a JSON object with these keys:
- "summary": string
- "what_you_should_do_next": array of strings (3-7 items)
- "risks_or_blockers": array of strings (0-6 items)
- "suggested_schedule": array of objects with keys: "day" (string), "focus" (string)

Do not include any markdown blocks or code fences. Output JSON only.

Milestone: {milestone}
Tasks: {tasks}
"""

SUBTASK_GENERATION_PROMPT = """You generate checklist subtasks for one parent task.

Return EXACTLY a JSON object with this shape:
{{"suggestions":[{{"title":"short action"}}]}}

Rules:
- Produce 4 to 7 suggestions.
- Titles must be short, actionable, non-empty, and under 200 characters.
- Do not duplicate existing subtasks.
- Output JSON only.

Plan: {plan_title}
Milestone: {milestone_title}
Parent task: {task_title}
Task description: {task_description}
Existing subtasks: {existing_subtasks}
"""


def _strip_code_fences(content: str) -> str:
    c = (content or "").strip()
    if c.startswith("```json"):
        c = c[7:]
    if c.startswith("```"):
        c = c[3:]
    if c.endswith("```"):
        c = c[:-3]
    return c.strip()


def _extract_json_object(content: str) -> str:
    """Best-effort extraction of a JSON object from model output."""
    c = _strip_code_fences(content)
    match = re.search(r"\{[\s\S]*\}", c)
    return match.group(0) if match else c


def _try_parse_json(content: str) -> tuple[dict | None, str]:
    raw = _extract_json_object(content)
    try:
        return json.loads(raw), raw
    except Exception:
        return None, raw


# ── Preferences ────────────────────────────────────────────────────────────────

@router.get("/preferences", response_model=UserPreferencesResponse)
async def get_preferences(
    user_id: UUID = Depends(get_current_user),
):
    prefs = adaptive_store.ensure_preferences(user_id)
    return UserPreferencesResponse(
        user_id=prefs.user_id,
        max_tasks_per_day=prefs.max_tasks_per_day,
        created_at=prefs.created_at,
        updated_at=prefs.updated_at,
    )


@router.put("/preferences", response_model=UserPreferencesResponse)
async def update_preferences(
    payload: UserPreferencesUpdate,
    user_id: UUID = Depends(get_current_user),
):
    prefs = adaptive_store.update_preferences(user_id, payload.max_tasks_per_day)
    if prefs is None:
        prefs = adaptive_store.create_preferences(user_id, payload.max_tasks_per_day)
    return UserPreferencesResponse(
        user_id=prefs.user_id,
        max_tasks_per_day=prefs.max_tasks_per_day,
        created_at=prefs.created_at,
        updated_at=prefs.updated_at,
    )


# ── Scheduler ──────────────────────────────────────────────────────────────────

@router.get("/scheduler/daily", response_model=DailyTasksResponse)
async def get_daily_tasks(
    on_date: date | None = None,
    user_id: UUID = Depends(get_current_user),
):
    target_date = on_date or date.today()
    result = scheduler_service.get_daily_tasks(user_id, target_date)
    return _daily_schedule_response(result)


@router.post("/scheduler/daily/pull-extra", response_model=DailyTasksResponse)
async def pull_extra_daily_tasks(
    payload: PullExtraTasksRequest,
    user_id: UUID = Depends(get_current_user),
):
    result = scheduler_service.pull_extra_tasks(user_id, payload.count, date.today())
    return _daily_schedule_response(result)


@router.delete("/scheduler/daily/batch")
async def clear_daily_batch(
    user_id: UUID = Depends(get_current_user),
):
    """Clear the locked daily batch cache to force recalculation."""
    adaptive_store.clear_daily_task_batch(user_id, date.today())
    return {"status": "cleared"}


# ── Events ─────────────────────────────────────────────────────────────────────

@router.post("/events", response_model=EventResponse)
async def create_event(
    payload: EventCreateRequest,
    user_id: UUID = Depends(get_current_user),
):
    event = events_service.record(
        user_id=user_id,
        task_id=payload.task_id,
        plan_id=payload.plan_id,
        event_type=payload.event_type,
        feedback_rating=payload.feedback_rating,
        feedback_text=payload.feedback_text,
    )
    return EventResponse(
        id=event.id,
        user_id=event.user_id,
        task_id=event.task_id,
        plan_id=event.plan_id,
        event_type=event.event_type,
        feedback_rating=event.feedback_rating,
        feedback_text=event.feedback_text,
        created_at=event.created_at,
    )


@router.get("/events", response_model=list[EventResponse])
async def list_events(
    task_id: UUID | None = None,
    event_type: EventType | None = None,
    user_id: UUID = Depends(get_current_user),
):
    if task_id:
        events = adaptive_store.get_events_for_task(task_id)
    else:
        events = adaptive_store.get_events_for_user(user_id, event_type=event_type)
    return [
        EventResponse(
            id=e.id,
            user_id=e.user_id,
            task_id=e.task_id,
            plan_id=e.plan_id,
            event_type=e.event_type,
            feedback_rating=e.feedback_rating,
            feedback_text=e.feedback_text,
            created_at=e.created_at,
        )
        for e in events
    ]


# ── Task Management ────────────────────────────────────────────────────────────

@router.get("/tasks/today", response_model=list[TaskResponse])
async def get_tasks_today(
    user_id: UUID = Depends(get_current_user),
):
    try:
        tasks = adaptive_store.get_tasks_for_date(user_id, date.today())
        return _tasks_with_indices(tasks)
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error(f"Error in get_tasks_today: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"get_tasks_today failed: {str(e)}")


@router.get("/tasks/today/v2", response_model=list[TaskResponse])
async def get_tasks_today_v2(
    user_id: UUID = Depends(get_current_user),
):
    """Backward-compatible V2 endpoint backed by the adaptive scheduler."""
    if not _v2_enabled:
        return await get_tasks_today(user_id=user_id)

    try:
        today = date.today()
        result = scheduler_service.get_daily_tasks(user_id, today)
        return _tasks_with_indices(result["tasks"])
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error(f"Error in get_tasks_today_v2: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"get_tasks_today_v2 failed: {str(e)}")


@router.post("/tasks/update", response_model=TaskResponse)
async def update_task_status(
    payload: TaskUpdateRequest,
    user_id: UUID = Depends(get_current_user),
):
    return await _complete_task_status_flow(
        task_id=payload.task_id,
        status=payload.status,
        user_id=user_id,
        feedback_text=payload.feedback_text,
    )


async def _complete_task_status_flow(
    task_id: UUID,
    status: TaskStatus,
    user_id: UUID,
    feedback_text: str | None = None,
) -> TaskResponse:
    try:
        task = adaptive_store.get_task(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")

        if status == TaskStatus.pending:
            # Undoing a task - delete history record if it exists
            adaptive_store.delete_task_history(task.id)
            updated = adaptive_store.update_task_status(task.id, TaskStatus.pending)
            if updated is None:
                raise HTTPException(status_code=500, detail="Failed to update task to pending")
            return _task_to_response(updated)

        # Map status → event type
        status_to_event = {
            TaskStatus.done: EventType.done,
            TaskStatus.skipped: EventType.skipped,
            TaskStatus.partial: EventType.partial,
        }
        event_type = status_to_event.get(status)
        if event_type is None:
            raise HTTPException(status_code=400, detail=f"Cannot update to status '{status.value}'. Only done, skipped, partial allowed.")

        # Record event (also updates task status internally)
        events_service.record(
            user_id=user_id,
            task_id=task.id,
            plan_id=task.plan_id,
            event_type=event_type,
            feedback_text=feedback_text,
        )

        # Create history record when task is marked done
        if status == TaskStatus.done:
            plan = adaptive_store.get_plan(task.plan_id)
            milestone_name = None
            task_index = 0  # 1-based position in plan roadmap
            if task.milestone_id:
                milestones = adaptive_store.get_milestones_for_plan(user_id, task.plan_id)
                # Calculate task_index: position across all milestones
                all_task_ids = []
                for ms in sorted(milestones, key=lambda m: m.order_index):
                    ms_tasks = adaptive_store.get_tasks_for_milestone(user_id, ms.id)
                    all_task_ids.extend([t.id for t in sorted(ms_tasks, key=lambda t: t.order_index)])
                try:
                    task_index = all_task_ids.index(task.id) + 1  # 1-based
                except ValueError:
                    task_index = len(all_task_ids) + 1  # fallback
                for ms in milestones:
                    if ms.id == task.milestone_id:
                        milestone_name = ms.title
                        break
            else:
                # No milestone - calculate from all plan tasks
                plan_tasks = adaptive_store.get_tasks_for_plan(task.plan_id)
                all_task_ids = [t.id for t in sorted(plan_tasks, key=lambda t: t.order_index)]
                try:
                    task_index = all_task_ids.index(task.id) + 1
                except ValueError:
                    task_index = len(all_task_ids) + 1
            # Get working_day_index from daily batch metadata if available
            working_day_index = None
            batch = adaptive_store.get_daily_task_batch(user_id, task.due_date or date.today())
            if batch and batch.get("metadata"):
                metadata = batch.get("metadata", {})
                if isinstance(metadata, dict):
                    plans_wd = metadata.get("plans_working_day", {})
                    working_day_index = plans_wd.get(str(task.plan_id))
            try:
                adaptive_store.create_task_history(
                    user_id=user_id,
                    task_id=task.id,
                    task_index=task_index,
                    task_name=task.title,
                    plan_id=task.plan_id,
                    plan_name=plan.title if plan else "Untitled Plan",
                    milestone_id=task.milestone_id,
                    milestone_name=milestone_name,
                    plan_completed=False,  # Will be updated if plan completes
                    working_day_index=working_day_index,
                    calendar_date=task.due_date,
                )
            except Exception as e:
                logger.warning("Failed to create task history: %s", e)

        # Auto-adjustment: if skipped, reschedule to tomorrow
        if status == TaskStatus.skipped:
            adjuster_service.handle_skip(user_id, task.id)

        # Real-time adaptation: trigger adaptation engine on any status change
        try:
            on_task_status_changed(user_id, task.id, status)
        except Exception as e:
            logger.warning("Real-time adaptation trigger failed: %s", e)

        # Auto milestone completion check when task is done
        if status == TaskStatus.done and task.milestone_id:
            try:
                is_complete = adaptive_store.check_milestone_completion(user_id, task.milestone_id)
                if is_complete:
                    ms = adaptive_store.update_milestone(user_id, task.milestone_id, {"status": MilestoneStatus.completed})
                    if ms:
                        next_ms = adaptive_store.activate_next_milestone(user_id, ms.plan_id)
                        if next_ms:
                            try:
                                await generate_for_milestone(str(next_ms.id), str(user_id), adaptive_store)
                            except Exception as e:
                                logger.warning("Task generation for milestone %s failed: %s", next_ms.id, e)
                        # Trigger deep review on milestone completion
                        try:
                            deep_review_service.on_milestone_completed(user_id, task.milestone_id)
                        except Exception as e:
                            logger.warning("Deep review trigger on milestone failed: %s", e)
            except Exception as e:
                logger.warning("Auto milestone check failed: %s", e)

        updated = adaptive_store.get_task(task.id)
        if updated is None:
            task.status = status
            updated = task
        return _task_to_response(updated)
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error(f"Error in update_task_status: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"update_task_status failed: {str(e)}")



# ── Task Detail (lazy generation) ──────────────────────────────────────────────

@router.get("/tasks/{task_id}/subtasks", response_model=list[SubtaskResponse])
async def list_subtasks(
    task_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    task = _require_user_task(task_id, user_id)
    return [_subtask_to_response(s) for s in adaptive_store.list_subtasks_by_task(task.id)]


@router.post("/tasks/{task_id}/subtasks", response_model=SubtaskResponse)
async def create_subtask(
    task_id: UUID,
    payload: SubtaskCreateRequest,
    user_id: UUID = Depends(get_current_user),
):
    task = _require_user_task(task_id, user_id)
    order_index = adaptive_store.next_subtask_order_index(task.id)
    subtask = adaptive_store.create_subtask(task.id, payload.title, order_index)
    return _subtask_to_response(subtask)


@router.post("/tasks/{task_id}/subtasks/generate", response_model=GenerateSubtasksResponse)
async def generate_subtasks(
    task_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    task = _require_user_task(task_id, user_id)
    plan = adaptive_store.get_plan(task.plan_id)
    milestone_title = "None"
    if task.milestone_id:
        milestones = adaptive_store.get_milestones_for_plan(user_id, task.plan_id)
        milestone = next((ms for ms in milestones if ms.id == task.milestone_id), None)
        if milestone:
            milestone_title = milestone.title

    existing = adaptive_store.list_subtasks_by_task(task.id)
    prompt = SUBTASK_GENERATION_PROMPT.format(
        plan_title=plan.title if plan else "Untitled Plan",
        milestone_title=milestone_title,
        task_title=task.title,
        task_description=task.description or "None",
        existing_subtasks=", ".join(s.title for s in existing) or "None",
    )
    try:
        parsed, raw = _try_parse_json(chatResponse(prompt))
    except LLMProviderError as exc:
        logger.warning("Subtask generation failed for task %s: %s", task.id, exc)
        raise HTTPException(status_code=503, detail="AI subtask generation is temporarily unavailable.")
    except Exception as exc:
        logger.warning("Subtask generation failed for task %s: %s", task.id, exc)
        raise HTTPException(status_code=503, detail="AI subtask generation failed.")

    if not parsed or not isinstance(parsed.get("suggestions"), list):
        logger.warning("Invalid subtask generation response for task %s: %s", task.id, raw)
        raise HTTPException(status_code=503, detail="AI returned an invalid subtask response.")

    suggestions: list[SubtaskSuggestion] = []
    seen: set[str] = set()
    for item in parsed["suggestions"]:
        title = item.get("title") if isinstance(item, dict) else item
        if not isinstance(title, str):
            continue
        title = title.strip()
        normalized = title.lower()
        if not title or len(title) >= 200 or normalized in seen:
            continue
        seen.add(normalized)
        suggestions.append(SubtaskSuggestion(title=title))

    if len(suggestions) < 4:
        raise HTTPException(status_code=503, detail="AI returned too few valid subtask suggestions.")
    return GenerateSubtasksResponse(suggestions=suggestions[:7])


@router.patch("/subtasks/{subtask_id}", response_model=SubtaskResponse)
async def update_subtask(
    subtask_id: UUID,
    payload: SubtaskUpdateRequest,
    user_id: UUID = Depends(get_current_user),
):
    existing = adaptive_store.get_subtask(subtask_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="Subtask not found")
    task = _require_user_task(existing.task_id, user_id)

    updated = adaptive_store.update_subtask(
        subtask_id,
        title=payload.title,
        completed=payload.completed,
        order_index=payload.order_index,
    )
    if updated is None:
        raise HTTPException(status_code=500, detail="Failed to update subtask")

    should_auto_complete = (
        payload.completed is True
        and existing.completed is False
        and task.status != TaskStatus.done
        and adaptive_store.all_subtasks_completed(task.id)
    )
    if should_auto_complete:
        try:
            await _complete_task_status_flow(task.id, TaskStatus.done, user_id)
        except Exception:
            adaptive_store.update_subtask(
                subtask_id,
                title=existing.title,
                completed=existing.completed,
                order_index=existing.order_index,
            )
            raise

    return _subtask_to_response(updated)


@router.delete("/subtasks/{subtask_id}")
async def delete_subtask(
    subtask_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    existing = adaptive_store.get_subtask(subtask_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="Subtask not found")
    _require_user_task(existing.task_id, user_id)
    if not adaptive_store.delete_subtask(subtask_id):
        raise HTTPException(status_code=500, detail="Failed to delete subtask")
    return {"deleted": True}


@router.get("/tasks/{task_id}/subtasks/count", response_model=SubtaskCountsResponse)
async def count_subtasks(
    task_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    task = _require_user_task(task_id, user_id)
    return SubtaskCountsResponse(**adaptive_store.count_subtasks_by_task(task.id))


@router.get("/tasks/{task_id}/subtasks/all-completed")
async def all_subtasks_completed(
    task_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    task = _require_user_task(task_id, user_id)
    return {"allCompleted": adaptive_store.all_subtasks_completed(task.id)}


@router.get("/tasks/{task_id}/detail", response_model=TaskDetailResponse)
async def get_task_detail(
    task_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    task = adaptive_store.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    # If detail already cached, return it — but regenerate if key fields are missing
    # (e.g. old cache generated before expert_tip was added to the prompt)
    if task.detail_json and "expert_tip" in task.detail_json:
        return TaskDetailResponse(
            task_id=task.id,
            detail=task.detail_json,
            generated=False,
        )

    # Lazy-generate detail via LLM
    plan = adaptive_store.get_plan(task.plan_id)
    plan_context = ""
    if plan and plan.title:
        plan_context = plan.title

    # Gather user memory for context
    all_memory = adaptive_store.list_memory(user_id)
    user_memory = {m.key.value: m.value for m in all_memory}

    # Build context-aware system prompt for personalised guide
    system_prompt = None
    try:
        session = {"active_tab": "today", "open_plan_id": str(task.plan_id), "open_task_id": str(task_id)}
        system_prompt = await build_context(str(user_id), session, adaptive_store)
    except Exception as e:
        logger.warning("context_builder failed for task detail: %s", e)

    detail = task_detail_generator_service.generate_task_detail(
        task_id=task.id,
        task_title=task.title,
        plan_context=plan_context,
        user_memory=user_memory,
        system=system_prompt,
    )

    # Cache on the task record
    adaptive_store.update_task_detail_json(task.id, detail)

    return TaskDetailResponse(
        task_id=task.id,
        detail=detail,
        generated=True,
    )


# ── Automatic Adjustments ─────────────────────────────────────────────────────

@router.post("/tasks/{task_id}/reschedule", response_model=TaskResponse)
async def reschedule_task(
    task_id: UUID,
    new_date: date,
    user_id: UUID = Depends(get_current_user),
):
    task = adaptive_store.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    updated = adaptive_store.reschedule_task(task_id, new_date)
    if updated:
        adaptive_store.record_event(
            user_id=user_id,
            task_id=task_id,
            plan_id=task.plan_id,
            event_type=EventType.rescheduled,
            feedback_text=f"manually rescheduled to {new_date.isoformat()}",
        )
    return _task_to_response(adaptive_store.get_task(task_id))


@router.post("/tasks/busy", response_model=list[TaskResponse])
async def mark_busy(
    user_id: UUID = Depends(get_current_user),
):
    rescheduled = adjuster_service.handle_busy(user_id)
    return _tasks_with_indices(rescheduled)


@router.post("/tasks/overflow", response_model=list[TaskResponse])
async def reschedule_overflow(
    user_id: UUID = Depends(get_current_user),
):
    rescheduled = adjuster_service.reschedule_overflow(user_id)
    return _tasks_with_indices(rescheduled)


@router.post("/tasks/pull-next", response_model=TaskResponse)
async def pull_next_task(
    plan_id: UUID | None = None,
    user_id: UUID = Depends(get_current_user),
):
    task = adjuster_service.pull_next_task(user_id, plan_id)
    if task is None:
        raise HTTPException(status_code=404, detail="No pending tasks available to pull")
    return _task_to_response(task)


# ── Deep Review ─────────────────────────────────────────────────────────────

@router.post("/deep-review")
async def run_deep_review(
    trigger_reason: str = "Manual trigger",
    plan_id: UUID | None = None,
    user_id: UUID = Depends(get_current_user),
):
    """Run a deep review (LLM-assisted plan adjustments).
    Triggered automatically on milestone completion or failure thresholds,
    but can also be called manually.
    """
    result = deep_review_service.run_deep_review(
        user_id,
        trigger_reason=trigger_reason,
        plan_id_filter=plan_id,
    )
    return result


# ── Task shortcuts ─────────────────────────────────────────────────────────────

@router.post("/tasks/{task_id}/skip", response_model=TaskResponse)
async def skip_task(
    task_id: UUID,
    payload: SkipRequest = SkipRequest(),
    user_id: UUID = Depends(get_current_user),
):
    task = adaptive_store.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    if payload.skip_type == SkipType.skip_permanently:
        # Permanent skip: mark as skipped with reason, no reschedule
        updated = adaptive_store.set_task_skipped_permanently(
            task_id, reason=payload.feedback_text,
        )
        events_service.record(
            user_id=user_id,
            task_id=task_id,
            plan_id=task.plan_id,
            event_type=EventType.skipped,
            feedback_text=payload.feedback_text,
        )
        # Save skip reason as memory pattern
        if payload.feedback_text:
            try:
                adaptive_store.create_memory(
                    user_id=user_id,
                    key=MemoryKey.pattern,
                    value=f"Skipped task '{task.title}' permanently: {payload.feedback_text}",
                    source="skip_action",
                )
            except Exception as e:
                logger.warning("Failed to save skip reason as memory: %s", e)
    else:
        # Skip today: reschedule to next working day
        plan = adaptive_store.get_plan(task.plan_id)
        working_days = None
        if plan and plan.schedule_prefs:
            working_days = plan.schedule_prefs.get("working_days")
        next_day = get_next_working_day(date.today(), working_days)
        try:
            updated = adaptive_store.set_task_rescheduled(task_id, next_day, task.due_date or date.today())
        except Exception:
            updated = adaptive_store.reschedule_task(task_id, next_day)
        adaptive_store.increment_carry_over(task_id)
        events_service.record(
            user_id=user_id,
            task_id=task_id,
            plan_id=task.plan_id,
            event_type=EventType.skipped,
            feedback_text=payload.feedback_text,
        )

    # Real-time adaptation: recalculate workload immediately after skip
    try:
        on_task_skipped(user_id, task_id, skip_type=payload.skip_type.value)
    except Exception as e:
        logger.warning("Real-time adaptation on skip failed: %s", e)

    updated = adaptive_store.get_task(task_id)
    if updated is None:
        updated = task
    return _task_to_response(updated)


@router.post("/tasks/{task_id}/feedback", response_model=EventResponse)
async def submit_feedback(
    task_id: UUID,
    payload: FeedbackRequest,
    user_id: UUID = Depends(get_current_user),
):
    task = adaptive_store.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    event = events_service.record(
        user_id=user_id,
        task_id=task_id,
        plan_id=task.plan_id,
        event_type=EventType.feedback,
        feedback_rating=payload.feedback_rating,
        feedback_text=payload.feedback_text,
    )
    return EventResponse(
        id=event.id,
        user_id=event.user_id,
        task_id=event.task_id,
        plan_id=event.plan_id,
        event_type=event.event_type,
        feedback_rating=event.feedback_rating,
        feedback_text=event.feedback_text,
        created_at=event.created_at,
    )


# ── Memory ─────────────────────────────────────────────────────────────────────

@router.post("/memory", response_model=MemoryResponse)
async def create_memory(
    payload: MemoryCreateRequest,
    user_id: UUID = Depends(get_current_user),
):
    mem = adaptive_store.create_memory(
        user_id=user_id,
        key=payload.key,
        value=payload.value,
        source=payload.source,
        importance=payload.importance,
        confidence=payload.confidence,
        user_visible=payload.user_visible,
        goal_id=payload.goal_id,
    )
    return _memory_to_response(mem)


@router.get("/memory", response_model=list[MemoryResponse])
async def list_memory(
    key: MemoryKey | None = None,
    user_id: UUID = Depends(get_current_user),
):
    mems = adaptive_store.list_memory(user_id, key=key)
    return [_memory_to_response(m) for m in mems]


@router.delete("/memory/{memory_id}")
async def delete_memory(
    memory_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    mem = adaptive_store.get_memory(memory_id)
    if mem is None or mem.user_id != user_id:
        raise HTTPException(status_code=404, detail="Memory item not found")
    # Delete via Supabase
    res = adaptive_store.client.table("memory").delete().eq("id", str(memory_id)).eq("user_id", str(user_id)).execute()
    return {"deleted": True}


@router.post("/memory/extract", response_model=ExtractMemoryResponse)
async def extract_memory_v2(
    payload: ExtractMemoryRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Extract structured memory from conversation with hybrid policy.

    Auto-saves preference/pattern/schedule_habit; returns goal/deadline/constraint
    as suggestions needing user confirmation."""
    conversation = [{"role": "user", "content": payload.conversation}]
    result = await extract_and_save(str(user_id), conversation, adaptive_store)
    all_items = result.all_items
    return ExtractMemoryResponse(
        extracted=[
            ExtractedField(key=item["key"], value=item["value"], id=item.get("id"))
            for item in all_items
        ],
        count=len(all_items),
    )


# ── Plans (adaptive extensions) ────────────────────────────────────────────────

@router.get("/plans", response_model=list[PlanResponse])
async def list_active_plans(
    user_id: UUID = Depends(get_current_user),
):
    try:
        plans = adaptive_store.list_active_plans(user_id)
        progress = adaptive_store.get_plan_progress_batch([p.id for p in plans]) if plans else {}
        task_counts = adaptive_store.count_tasks_batch([p.id for p in plans]) if plans else {}
        return [_plan_to_response(p, progress.get(str(p.id), 0.0), *task_counts.get(str(p.id), (0, 0))) for p in plans]
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error(f"Error in list_active_plans: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"list_active_plans failed: {str(e)}")


@router.get("/plans/all", response_model=list[PlanResponse])
async def list_all_plans(
    user_id: UUID = Depends(get_current_user),
):
    """All plans including paused and completed."""
    try:
        plans = adaptive_store.list_all_plans(user_id)
        progress = adaptive_store.get_plan_progress_batch([p.id for p in plans]) if plans else {}
        task_counts = adaptive_store.count_tasks_batch([p.id for p in plans]) if plans else {}
        return [_plan_to_response(p, progress.get(str(p.id), 0.0), *task_counts.get(str(p.id), (0, 0))) for p in plans]
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error(f"Error in list_all_plans: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"list_all_plans failed: {str(e)}")


@router.delete("/plans/{plan_id}")
async def delete_plan(
    plan_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")
    # Delete tasks, milestones, then plan
    adaptive_store.client.table("tasks").delete().eq("plan_id", str(plan_id)).execute()
    adaptive_store.client.table("milestones").delete().eq("plan_id", str(plan_id)).execute()
    adaptive_store.client.table("plans").delete().eq("id", str(plan_id)).execute()
    return {"deleted": True}


@router.post("/plans/generate", response_model=CreatePlanResponse)
@limit_10_per_minute  # Plan generation is expensive when slowapi is available
async def generate_plan(
    request: Request,  # Required by slowapi
    payload: CreatePlanRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Alias for /create-plan — same logic, friendlier URL."""
    result = plan_generator_service.create_plan_from_memory(user_id, payload.memory_id)
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])

    plan = result["plan"]
    milestone_results = result["milestones"]
    total_tasks = sum(len(ms["tasks"]) for ms in milestone_results)

    milestone_responses = []
    for ms_data in milestone_results:
        ms = ms_data["milestone"]
        tasks = ms_data["tasks"]
        milestone_responses.append(_milestone_to_response(ms, tasks))

    # Clear today's batch so scheduler includes new plan's tasks
    adaptive_store.clear_daily_task_batch(user_id, date.today())

    return CreatePlanResponse(
        plan=PlanResponse(
            id=plan.id,
            goal_id=plan.goal_id,
            memory_id=getattr(plan, 'memory_id', None),
            user_id=plan.user_id,
            title=plan.title,
            status=plan.status,
            priority=plan.priority,
            intensity=plan.intensity,
            created_at=plan.created_at,
            updated_at=plan.updated_at,
        ),
        milestones=milestone_responses,
        task_count=total_tasks,
    )


GENERATE_FROM_ANSWERS_PROMPT = """You are a world-class learning plan architect. Given a learner's answers, create a detailed, milestone-structured learning roadmap.

Break the plan into 4–6 milestones (called "steps"), each with 3–6 tasks (called "courses" or "learning activities"). Make the first step immediately actionable. Each step should build on the previous one.

Return EXACTLY a JSON object with these keys:
- "plan_title": string — concise, specific plan title (e.g. "Advanced Python for AI Engineering")
- "plan_summary": string — 1-2 sentence overview
- "duration_weeks": number — estimated total weeks
- "milestones": array of objects, each with:
    - "title": string — step title (e.g. "Building Intelligent AI Agents")
    - "description": string — what this step achieves
    - "order_index": number (0-based)
    - "tasks": array of objects, each with:
        - "title": string — specific, actionable task name (e.g. "Implementing Agentic Workflows with LangGraph")
        - "description": string — brief description
        - "duration_minutes": number
        - "order_index": number (0-based)

Do not include any markdown blocks. Output raw JSON only.

Learner's goal: {learning_goal}
Focus area: {focus_area}
Current skill level: {skill_level}
Things to focus on or avoid: {focus_or_avoid}
Additional context: {extra_context}
Today's date: {today}"""


@router.post("/plans/generate-from-answers", response_model=CreatePlanResponse)
@limit_10_per_minute  # Plan generation is expensive when slowapi is available
async def generate_plan_from_answers(
    request: Request,  # Required by slowapi
    payload: GenerateFromAnswersRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Generate a full plan from the 5-question AI wizard — no memory_id needed."""
    from datetime import date as _date
    import json as _json

    prompt = GENERATE_FROM_ANSWERS_PROMPT.format(
        learning_goal=payload.learning_goal,
        focus_area=payload.focus_area,
        skill_level=payload.skill_level,
        focus_or_avoid=payload.focus_or_avoid or "none specified",
        extra_context=payload.extra_context or "none",
        today=_date.today().isoformat(),
    )

    try:
        content = chatResponse(prompt)
        content = _strip_code_fences(content)
        parsed = _json.loads(content)
    except Exception as exc:
        logger.error(f"generate_plan_from_answers LLM failed: {exc}")
        # Fallback: simple 3-step plan
        parsed = {
            "plan_title": f"{payload.focus_area[:60]} Learning Plan",
            "plan_summary": f"A structured plan to help you achieve: {payload.learning_goal}",
            "duration_weeks": 12,
            "milestones": [
                {"title": "Foundations", "description": "Get the core basics in place", "order_index": 0,
                 "tasks": [{"title": "Research and set up your learning environment", "description": "", "duration_minutes": 60, "order_index": 0},
                           {"title": "Complete an introductory course or tutorial", "description": "", "duration_minutes": 90, "order_index": 1}]},
                {"title": "Core Skills", "description": "Build the essential skills", "order_index": 1,
                 "tasks": [{"title": "Work through key concepts with hands-on exercises", "description": "", "duration_minutes": 120, "order_index": 0},
                           {"title": "Build a small practice project", "description": "", "duration_minutes": 180, "order_index": 1}]},
                {"title": "Advanced Topics", "description": "Go deeper and apply knowledge", "order_index": 2,
                 "tasks": [{"title": "Study advanced topics specific to your goal", "description": "", "duration_minutes": 120, "order_index": 0},
                           {"title": "Build a complete project to demonstrate mastery", "description": "", "duration_minutes": 240, "order_index": 1}]},
            ],
        }

    milestones_data = parsed.get("milestones", [])
    title = parsed.get("plan_title", payload.focus_area[:60])

    # Create the plan record
    from backend.adaptive.models import PlanIntensity, PlanPriority, MilestoneStatus
    priority_map = {"Get a Job": PlanPriority.high, "Grow in my current role": PlanPriority.high}
    plan_priority = priority_map.get(payload.learning_goal, PlanPriority.medium)

    plan, _ = adaptive_store.create_plan_with_tasks(
        user_id=user_id,
        goal_id=None,
        title=title,
        priority=plan_priority,
        intensity=PlanIntensity.moderate,
        tasks=[],
    )

    result_milestones = []
    total_task_count = 0

    for ms_idx, ms_data in enumerate(milestones_data):
        ms_status = MilestoneStatus.active if ms_idx == 0 else MilestoneStatus.locked
        milestone = adaptive_store.create_milestone(
            user_id=user_id,
            plan_id=plan.id,
            data={
                "title": ms_data.get("title", f"Step {ms_idx + 1}"),
                "description": ms_data.get("description", ""),
                "order_index": ms_data.get("order_index", ms_idx),
                "status": ms_status,
            },
        )

        tasks_to_insert = []
        for t_data in ms_data.get("tasks", []):
            tasks_to_insert.append({
                "plan_id": str(plan.id),
                "milestone_id": str(milestone.id),
                "title": t_data.get("title", "Untitled task"),
                "description": t_data.get("description", ""),
                "duration_minutes": t_data.get("duration_minutes", 60),
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
        total_task_count += len(task_rows)
        result_milestones.append({"milestone": milestone, "tasks": task_rows})

    milestone_responses = [
        _milestone_to_response(ms_data["milestone"], ms_data["tasks"])
        for ms_data in result_milestones
    ]

    # Clear today's batch so scheduler includes new plan's tasks
    adaptive_store.clear_daily_task_batch(user_id, date.today())

    return CreatePlanResponse(
        plan=PlanResponse(
            id=plan.id,
            goal_id=plan.goal_id,
            memory_id=getattr(plan, 'memory_id', None),
            user_id=plan.user_id,
            title=plan.title,
            status=plan.status,
            priority=plan.priority,
            intensity=plan.intensity,
            created_at=plan.created_at,
            updated_at=plan.updated_at,
        ),
        milestones=milestone_responses,
        task_count=total_task_count,
    )


EXTRACT_WIZARD_FIELDS_PROMPT = """You are a data extraction engine. Analyze these user messages and extract the following fields if they can be determined. If a field cannot be determined, leave it as null.

Return EXACTLY a JSON object with these keys:
- "learning_goal": string or null — the user's main learning goal category (e.g. "Get a Job", "Grow in my current role", "Build Projects / Side Hustles", "Strengthen Fundamentals", "Explore a New Field")
- "focus_area": string or null — the role or field the user wants to focus on, with detail (e.g. "I know intermediate JavaScript and want to focus on advanced aspects")
- "skill_level": string or null — current skill level (e.g. "Beginner", "Intermediate", "Advanced")
- "focus_or_avoid": string or null — specific things to focus on or avoid (e.g. "focus on vanilla JavaScript, avoid frameworks")
- "extra_context": string or null — any additional context about the user's goals or situation

Do not include any markdown blocks. Output raw JSON only.

User messages:
{user_messages}"""


@router.post("/plans/extract-from-chat", response_model=ExtractFromChatResponse)
async def extract_fields_from_chat(
    payload: ExtractFromChatRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Phase 1 — Extract wizard fields from the user's own chat messages only.

    Returns which fields were found and which are still missing so the frontend
    can render targeted MCQ / text prompts for only the gaps.
    """
    import json as _json

    # Join only the user's messages, numbered for clarity
    user_text = "\n".join(
        f"{i + 1}. {msg}" for i, msg in enumerate(payload.user_messages)
    )

    extract_prompt = EXTRACT_WIZARD_FIELDS_PROMPT.format(user_messages=user_text)
    try:
        content = chatResponse(extract_prompt)
        content = _strip_code_fences(content)
        fields = _json.loads(content)
    except Exception as exc:
        logger.error(f"extract_fields_from_chat LLM failed: {exc}")
        fields = {}

    required_fields = {
        "learning_goal": "What is your main learning goal? (e.g. Get a Job, Grow in my current role, Build Projects / Side Hustles, Strengthen Fundamentals, Explore a New Field)",
        "focus_area": "What role or field do you want to focus on? Describe in detail what you would like to focus on.",
        "skill_level": "What is your current skill level in this area? (Beginner, Intermediate, or Advanced)",
    }

    missing: list[MissingField] = []
    for field_key, question in required_fields.items():
        val = fields.get(field_key)
        if not val or not isinstance(val, str) or val.strip() in ("", "null"):
            missing.append(MissingField(field=field_key, question=question))
            fields[field_key] = None
        else:
            fields[field_key] = val.strip()

    # Normalise optional fields
    for opt in ("focus_or_avoid", "extra_context"):
        val = fields.get(opt)
        fields[opt] = val.strip() if val and val != "null" else None

    return ExtractFromChatResponse(
        extracted=fields,
        missing_fields=missing,
        ready=len(missing) == 0,
    )


@router.post("/plans/generate-from-chat", response_model=GenerateFromChatResponse)
async def generate_plan_from_chat(
    payload: GenerateFromChatRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Phase 2 — Receive fully-filled wizard fields and generate a plan.

    The frontend has already extracted (Phase 1) and asked the user to fill any
    missing fields; by the time this endpoint is called all 3 required fields are
    guaranteed to be present.  Uses the identical prompt as the wizard tab.
    """
    import json as _json
    from datetime import date as _date
    from backend.adaptive.models import PlanIntensity, PlanPriority, MilestoneStatus

    learning_goal = payload.learning_goal
    focus_area = payload.focus_area
    skill_level = payload.skill_level
    focus_or_avoid = payload.focus_or_avoid or "none specified"
    extra_context = payload.extra_context or "none"

    prompt = GENERATE_FROM_ANSWERS_PROMPT.format(
        learning_goal=learning_goal,
        focus_area=focus_area,
        skill_level=skill_level,
        focus_or_avoid=focus_or_avoid,
        extra_context=extra_context,
        today=_date.today().isoformat(),
    )

    try:
        content = chatResponse(prompt)
        content = _strip_code_fences(content)
        parsed = _json.loads(content)
    except Exception as exc:
        logger.error(f"generate_plan_from_chat LLM failed: {exc}")
        parsed = {
            "plan_title": f"{focus_area[:60]} Learning Plan",
            "plan_summary": f"A structured plan to help you achieve: {learning_goal}",
            "duration_weeks": 12,
            "milestones": [
                {"title": "Foundations", "description": "Get the core basics in place", "order_index": 0,
                 "tasks": [{"title": "Research and set up your learning environment", "description": "", "duration_minutes": 60, "order_index": 0},
                           {"title": "Complete an introductory course or tutorial", "description": "", "duration_minutes": 90, "order_index": 1}]},
                {"title": "Core Skills", "description": "Build the essential skills", "order_index": 1,
                 "tasks": [{"title": "Work through key concepts with hands-on exercises", "description": "", "duration_minutes": 120, "order_index": 0},
                           {"title": "Build a small practice project", "description": "", "duration_minutes": 180, "order_index": 1}]},
                {"title": "Advanced Topics", "description": "Go deeper and apply knowledge", "order_index": 2,
                 "tasks": [{"title": "Study advanced topics specific to your goal", "description": "", "duration_minutes": 120, "order_index": 0},
                           {"title": "Build a complete project to demonstrate mastery", "description": "", "duration_minutes": 240, "order_index": 1}]},
            ],
        }

    milestones_data = parsed.get("milestones", [])
    title = parsed.get("plan_title", focus_area[:60])

    priority_map = {"Get a Job": PlanPriority.high, "Grow in my current role": PlanPriority.high}
    plan_priority = priority_map.get(learning_goal, PlanPriority.medium)

    plan, _ = adaptive_store.create_plan_with_tasks(
        user_id=user_id,
        goal_id=None,
        title=title,
        priority=plan_priority,
        intensity=PlanIntensity.moderate,
        tasks=[],
    )

    result_milestones = []
    total_task_count = 0

    for ms_idx, ms_data in enumerate(milestones_data):
        ms_status = MilestoneStatus.active if ms_idx == 0 else MilestoneStatus.locked
        milestone = adaptive_store.create_milestone(
            user_id=user_id,
            plan_id=plan.id,
            data={
                "title": ms_data.get("title", f"Step {ms_idx + 1}"),
                "description": ms_data.get("description", ""),
                "order_index": ms_data.get("order_index", ms_idx),
                "status": ms_status,
            },
        )

        tasks_to_insert = []
        for t_data in ms_data.get("tasks", []):
            tasks_to_insert.append({
                "plan_id": str(plan.id),
                "milestone_id": str(milestone.id),
                "title": t_data.get("title", "Untitled task"),
                "description": t_data.get("description", ""),
                "duration_minutes": t_data.get("duration_minutes", 60),
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
        total_task_count += len(task_rows)
        result_milestones.append({"milestone": milestone, "tasks": task_rows})

    milestone_responses = [
        _milestone_to_response(ms_data["milestone"], ms_data["tasks"])
        for ms_data in result_milestones
    ]

    return GenerateFromChatResponse(
        ready=True,
        message=f"Your plan '{title}' is ready with {len(milestone_responses)} milestones and {total_task_count} tasks.",
        plan=PlanResponse(
            id=plan.id,
            goal_id=plan.goal_id,
            memory_id=getattr(plan, 'memory_id', None),
            user_id=plan.user_id,
            title=plan.title,
            status=plan.status,
            priority=plan.priority,
            intensity=plan.intensity,
            created_at=plan.created_at,
            updated_at=plan.updated_at,
        ),
        milestones=milestone_responses,
        task_count=total_task_count,
    )


@router.post("/plan/pause", response_model=PlanResponse)
async def pause_plan(
    payload: PlanControlRequest,
    user_id: UUID = Depends(get_current_user),
):
    plan = adaptive_store.get_plan(payload.plan_id)
    if plan is None or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Plan not found")
    if plan.status == PlanStatus.paused:
        raise HTTPException(status_code=400, detail="Plan is already paused")
    updated = adaptive_store.update_plan(payload.plan_id, status=PlanStatus.paused)
    if updated is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    return _plan_to_response(updated)


@router.post("/plan/resume", response_model=PlanResponse)
async def resume_plan(
    payload: PlanControlRequest,
    user_id: UUID = Depends(get_current_user),
):
    plan = adaptive_store.get_plan(payload.plan_id)
    if plan is None or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Plan not found")
    if plan.status != PlanStatus.paused:
        raise HTTPException(status_code=400, detail="Only paused plans can be resumed")
    updated = adaptive_store.update_plan(payload.plan_id, status=PlanStatus.active)
    if updated is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    return _plan_to_response(updated)


@router.post("/plan/update", response_model=PlanResponse)
async def update_plan(
    payload: PlanUpdateRequest,
    plan_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    plan = adaptive_store.get_plan(plan_id)
    if plan is None or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Plan not found")
    updated = adaptive_store.update_plan(
        plan_id,
        status=payload.status,
        priority=payload.priority,
        title=payload.title,
        intensity=payload.intensity,
    )
    if updated is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    return _plan_to_response(updated)


@router.patch("/plans/{plan_id}", response_model=PlanResponse)
async def patch_plan(
    plan_id: UUID,
    payload: PlanUpdateRequest,
    user_id: UUID = Depends(get_current_user),
):
    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")
    updated = adaptive_store.update_plan(
        plan_id,
        status=payload.status,
        priority=payload.priority,
        title=payload.title,
        intensity=payload.intensity,
    )
    if updated is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    return _plan_to_response(updated)


# ── Adapt Plan (schedule tasks across working days) ────────────────────────────

@router.post("/plans/{plan_id}/adapt", response_model=PlanResponse)
async def adapt_plan(
    plan_id: UUID,
    payload: AdaptPlanRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Distribute all pending tasks in a plan across working days within the deadline.

    Calculates the available working days between today and today+duration_days,
    then assigns each pending task a due_date spread evenly across those days.
    Also saves duration_days and working_days into plan.schedule_prefs.
    """
    from datetime import timedelta

    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")

    # Get all pending/partial tasks for this plan (ordered by milestone + order_index)
    tasks = [
        task for task in scheduler_service._ordered_tasks_for_plan(user_id, plan)
        if task.status in (TaskStatus.pending, TaskStatus.partial)
    ]
    start = date.today()
    deadline = start + timedelta(days=payload.duration_days - 1)
    next_prefs = {
        **(plan.schedule_prefs or {}),
        "working_days": payload.working_days,
        "start_date": start.isoformat(),
        "end_date": deadline.isoformat(),
    }

    if not tasks:
        # No tasks to schedule — just save prefs
        updated = adaptive_store.update_plan(
            plan_id,
            duration_days=payload.duration_days,
            schedule_prefs=next_prefs,
        )
        total_t, remaining_t = adaptive_store.count_tasks_for_plan(plan_id)
        return _plan_to_response(updated or plan, total_tasks=total_t, remaining_tasks=remaining_t)

    # Build list of working dates from today to today + duration_days
    working_dates: list[date] = []
    current = start
    while current <= deadline:
        # Python weekday(): Monday=0 … Sunday=6
        if current.weekday() in payload.working_days:
            working_dates.append(current)
        current += timedelta(days=1)

    if not working_dates:
        raise HTTPException(status_code=400, detail="No working days found in the given range")

    # Distribute tasks evenly across working days
    total_tasks = len(tasks)
    total_days = len(working_dates)
    base_per_day = total_tasks // total_days
    extra = total_tasks % total_days

    task_idx = 0
    for day_idx, work_date in enumerate(working_dates):
        count = base_per_day + (1 if day_idx < extra else 0)
        for _ in range(count):
            if task_idx >= total_tasks:
                break
            task = tasks[task_idx]
            adaptive_store.reschedule_task(task.id, work_date)
            task_idx += 1

    # Save schedule preferences on the plan
    updated = adaptive_store.update_plan(
        plan_id,
        duration_days=payload.duration_days,
        schedule_prefs=next_prefs,
    )

    # If plan was in 'setup' status, move it to 'active'
    if plan.status == PlanStatus.setup:
        updated = adaptive_store.update_plan(plan_id, status=PlanStatus.active)

    # Clear today's batch so scheduler recalculates with new task dates
    adaptive_store.clear_daily_task_batch(user_id, date.today())

    total_t, remaining_t = adaptive_store.count_tasks_for_plan(plan_id)
    return _plan_to_response(updated or plan, total_tasks=total_t, remaining_tasks=remaining_t)


# ── Plan Detail ──────────────────────────────────────────────────────────────────

PLAN_CHAT_SYSTEM_PROMPT = """You are Life Agent — an AI planning assistant embedded inside a Plan Detail view. You have full context about this plan, its milestones, and tasks.

When the user asks for changes, respond with a JSON block wrapped in ```plan-actions``` code fences containing an array of action objects. Each action has:
- "action": one of "reframe_milestone", "rename_milestone", "add_task", "remove_task", "reorder_task", "change_next_task", "split_milestone", "skip_task", "mark_blocked"
- "target_id": the UUID of the milestone or task being modified (if applicable)
- "params": object with action-specific parameters (e.g. {"title": "new name"}, {"description": "..."})

You may include explanatory text BEFORE the code fence. If no actions are needed, just respond with helpful text and no code fence.

Always be specific — reference actual milestone and task names from the plan context.

When a SELECTED TASK DETAIL section is present in the context, the user is focused on that specific task. Your primary role is to:
1. Help the user understand and complete that task — explain what it is, why it matters, and how to do it in practical terms.
2. Suggest relevant YouTube videos, articles, books, or other resources (beyond what's already listed) if the user asks for more learning material.
3. Give step-by-step guidance, tips, and encouragement tailored to that task's difficulty level.
4. Answer questions about the task concisely and practically.
5. If the user wants to modify the plan (skip task, add tasks, etc.), still support that with plan-actions."""


@router.get("/plans/{plan_id}/detail", response_model=PlanDetailResponse)
async def get_plan_detail(
    plan_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Full plan detail with aggregated stats, milestones, and tasks."""
    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")

    milestones = adaptive_store.get_milestones_for_plan(user_id, plan_id)

    # Aggregate stats
    total_tasks = 0
    completed_tasks = 0
    current_ms = None
    next_ms = None
    next_task = None

    for i, ms in enumerate(milestones):
        tasks = adaptive_store.get_tasks_for_milestone(user_id, ms.id)
        ms_tasks_count = len(tasks)
        ms_done = sum(1 for t in tasks if t.status.value == "done")
        total_tasks += ms_tasks_count
        completed_tasks += ms_done

        if ms.status.value == "active" and current_ms is None:
            current_ms = {"id": str(ms.id), "title": ms.title, "order_index": ms.order_index}
            # Next milestone
            if i + 1 < len(milestones):
                next_ms_item = milestones[i + 1]
                next_ms = {"id": str(next_ms_item.id), "title": next_ms_item.title, "order_index": next_ms_item.order_index}
            # Next pending task
            for t in tasks:
                if t.status.value == "pending" and next_task is None:
                    next_task = {"id": str(t.id), "title": t.title, "milestone_id": str(t.milestone_id) if t.milestone_id else None}

    completed_milestones = sum(1 for m in milestones if m.status.value == "completed")
    remaining_tasks = total_tasks - completed_tasks
    progress_pct = int((completed_tasks / total_tasks) * 100) if total_tasks > 0 else 0

    stats = PlanDetailStats(
        total_tasks=total_tasks,
        completed_tasks=completed_tasks,
        remaining_tasks=remaining_tasks,
        total_milestones=len(milestones),
        completed_milestones=completed_milestones,
        progress_pct=progress_pct,
        current_milestone=current_ms,
        next_milestone=next_ms,
        next_task=next_task,
    )

    milestone_responses = []
    for ms in milestones:
        tasks = adaptive_store.get_tasks_for_milestone(user_id, ms.id)
        milestone_responses.append(_milestone_to_response(ms, tasks))

    return PlanDetailResponse(
        plan=_plan_to_response(plan),
        stats=stats,
        milestones=milestone_responses,
    )


@router.get("/plans/{plan_id}/detail/v2", response_model=PlanDetailResponse)
async def get_plan_detail_v2(
    plan_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Optimized plan detail — eliminates N+1 queries.

    Instead of fetching tasks per-milestone (N queries), fetches ALL tasks
    for the plan in a single query and groups them in-memory.
    Falls back to V1 if the server-side _v2_enabled flag is False.
    """
    if not _v2_enabled:
        return await get_plan_detail(plan_id=plan_id, user_id=user_id)

    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")

    # Single query: all milestones for this plan
    milestones = adaptive_store.get_milestones_for_plan(user_id, plan_id)

    # Single query: all tasks for this plan (instead of N queries per milestone)
    res = (
        adaptive_store.client.table("tasks")
        .select()
        .eq("plan_id", str(plan_id))
        .order("order_index")
        .execute()
    )
    all_task_rows = [adaptive_store._map_task(row) for row in (res[1] if res and res[1] else [])]

    # Group tasks by milestone_id
    tasks_by_milestone: dict[str, list] = {}
    for t in all_task_rows:
        mid = str(t.milestone_id) if t.milestone_id else "__no_milestone__"
        tasks_by_milestone.setdefault(mid, []).append(t)

    # Aggregate stats (single pass over all_task_rows)
    total_tasks = len(all_task_rows)
    completed_tasks = sum(1 for t in all_task_rows if t.status.value == "done")
    current_ms = None
    next_ms = None
    next_task = None

    for i, ms in enumerate(milestones):
        ms_tasks = tasks_by_milestone.get(str(ms.id), [])
        if ms.status.value == "active" and current_ms is None:
            current_ms = {"id": str(ms.id), "title": ms.title, "order_index": ms.order_index}
            if i + 1 < len(milestones):
                next_ms_item = milestones[i + 1]
                next_ms = {"id": str(next_ms_item.id), "title": next_ms_item.title, "order_index": next_ms_item.order_index}
            for t in ms_tasks:
                if t.status.value == "pending" and next_task is None:
                    next_task = {"id": str(t.id), "title": t.title, "milestone_id": str(t.milestone_id) if t.milestone_id else None}

    completed_milestones = sum(1 for m in milestones if m.status.value == "completed")
    remaining_tasks = total_tasks - completed_tasks
    progress_pct = int((completed_tasks / total_tasks) * 100) if total_tasks > 0 else 0

    stats = PlanDetailStats(
        total_tasks=total_tasks,
        completed_tasks=completed_tasks,
        remaining_tasks=remaining_tasks,
        total_milestones=len(milestones),
        completed_milestones=completed_milestones,
        progress_pct=progress_pct,
        current_milestone=current_ms,
        next_milestone=next_ms,
        next_task=next_task,
    )

    milestone_responses = []
    for ms in milestones:
        ms_tasks = tasks_by_milestone.get(str(ms.id), [])
        milestone_responses.append(_milestone_to_response(ms, ms_tasks))

    return PlanDetailResponse(
        plan=_plan_to_response(plan),
        stats=stats,
        milestones=milestone_responses,
    )


@router.post("/plans/{plan_id}/chat", response_model=PlanChatResponse)
async def plan_chat(
    plan_id: UUID,
    payload: PlanChatRequest,
    user_id: UUID = Depends(get_current_user),
):
    """AI chat about a specific plan — returns reply + optional structured actions."""
    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")

    # Build plan-specific context summary (no heavy build_context call)
    milestones = adaptive_store.get_milestones_for_plan(user_id, plan_id)
    plan_summary_lines = [f"Plan: {plan.title} (status: {plan.status.value})"]
    for ms in milestones:
        tasks = adaptive_store.get_tasks_for_milestone(user_id, ms.id)
        done = sum(1 for t in tasks if t.status.value == "done")
        plan_summary_lines.append(
            f"  Milestone {ms.order_index + 1}: {ms.title} [{ms.status.value}] — {done}/{len(tasks)} tasks done"
        )
        for t in tasks[:8]:
            plan_summary_lines.append(f"    - {t.title} [{t.status.value}]")

    context_block = "\n".join(plan_summary_lines)

    # ── If a specific task is selected, append task detail context ────────────
    task_context_block = ""
    if payload.task_id:
        try:
            task = adaptive_store.get_task(UUID(payload.task_id))
            if task and task.detail_json:
                d = task.detail_json
                task_lines = [f"SELECTED TASK: {task.title} [status: {task.status.value}]"]
                if d.get("what_is_this"):
                    task_lines.append(f"  What is this: {d['what_is_this']}")
                if d.get("why_it_matters"):
                    task_lines.append(f"  Why it matters: {d['why_it_matters']}")
                if d.get("how_to_do_it"):
                    for step in d["how_to_do_it"]:
                        task_lines.append(f"  Step {step.get('step','?')}: {step.get('instruction','')}")
                if d.get("resources"):
                    for r in d["resources"]:
                        task_lines.append(f"  Resource [{r.get('type','link')}]: {r.get('title','')} — {r.get('description','')}")
                if d.get("expert_tip"):
                    task_lines.append(f"  Expert tip: {d['expert_tip']}")
                if d.get("todays_example"):
                    task_lines.append(f"  Today's example: {d['todays_example']}")
                if d.get("estimated_difficulty"):
                    task_lines.append(f"  Estimated difficulty: {d['estimated_difficulty']}")
                task_context_block = "\n\n=== SELECTED TASK DETAIL ===\n" + "\n".join(task_lines)
        except Exception as e:
            logger.warning("task_context_fetch_error=%s", e)

    # System prompt = plan context + (optional) task detail + plan chat instructions
    full_system = f"{PLAN_CHAT_SYSTEM_PROMPT}\n\n=== CURRENT PLAN CONTEXT ===\n{context_block}{task_context_block}"
    prompt = payload.message

    try:
        content = chatResponse(prompt, system=full_system)
    except Exception as exc:
        logger.exception("Plan chat LLM call failed")
        return PlanChatResponse(reply=f"Sorry, I couldn't process that: {exc}", actions=[])

    # Parse actions from ```plan-actions``` code fences
    actions: list[PlanChatAction] = []
    reply_text = content
    action_match = re.search(r"```plan-actions\s*\n([\s\S]*?)\n```", content)
    if action_match:
        try:
            action_json = json.loads(action_match.group(1))
            if isinstance(action_json, list):
                for a in action_json:
                    actions.append(PlanChatAction(
                        action=a.get("action", ""),
                        target_id=a.get("target_id"),
                        params=a.get("params", {}),
                    ))
            elif isinstance(action_json, dict):
                actions.append(PlanChatAction(
                    action=action_json.get("action", ""),
                    target_id=action_json.get("target_id"),
                    params=action_json.get("params", {}),
                ))
        except json.JSONDecodeError:
            pass
        # Remove the code fence from the reply text
        reply_text = content[:action_match.start()] + content[action_match.end():]
        reply_text = reply_text.strip()

    return PlanChatResponse(reply=reply_text, actions=actions)


# ── Today Chat ────────────────────────────────────────────────────────────────────

TODAY_CHAT_SYSTEM_PROMPT = """You are Life Agent — an AI planning assistant embedded inside the Today screen. You have full context about the user's daily schedule, their tasks for today, and which plans and milestones those tasks belong to.

Your role is to:
1. Help the user understand and complete their tasks for today — give practical, concise advice on how to tackle specific tasks.
2. Motivate and encourage the user — celebrate completed tasks, acknowledge progress, and help them stay on track.
3. Answer questions about their schedule — how many tasks remain, which plan a task belongs to, what milestone it's part of, how long a task should take.
4. Suggest time-management strategies — e.g. "Do the hard tasks first" or "Take a 5-min break after each task".
5. Help with adjustments — if the user feels overwhelmed, suggest skipping low-priority tasks or rescheduling. If they want to focus on a specific plan, help them prioritize those tasks.
6. When a SELECTED TASK DETAIL section is present, focus on that specific task — explain what it is, why it matters, and give step-by-step guidance.

When the user asks for changes to their schedule or tasks, respond with a JSON block wrapped in ```plan-actions``` code fences containing an array of action objects. Each action has:
- "action": one of "skip_task", "mark_blocked", "add_task", "remove_task"
- "target_id": the UUID of the task being modified (if applicable)
- "params": object with action-specific parameters (e.g. {"reason": "..."}, {"title": "..."})

You may include explanatory text BEFORE the code fence. If no actions are needed, just respond with helpful text and no code fence.

Always be specific — reference actual task names, plan names, and milestone names from the today context."""


@router.post("/today/chat", response_model=PlanChatResponse)
async def today_chat(
    payload: TodayChatRequest,
    user_id: UUID = Depends(get_current_user),
):
    """AI chat about today's schedule — returns reply + optional structured actions."""
    from datetime import date as _date

    today = _date.today()
    result = scheduler_service.get_daily_tasks(user_id, today)
    tasks = result.get("tasks", [])

    # Build today's context summary
    plan_ids = {t.plan_id for t in tasks}
    plans_by_id = {}
    for pid in plan_ids:
        plan = adaptive_store.get_plan(pid)
        if plan:
            plans_by_id[pid] = plan

    milestone_ids = {t.milestone_id for t in tasks if t.milestone_id}
    milestones_by_id = {}
    for pid, plan in plans_by_id.items():
        if not plan.user_id:
            continue
        for ms in adaptive_store.get_milestones_for_plan(plan.user_id, pid):
            if ms.id in milestone_ids:
                milestones_by_id[ms.id] = ms

    done_count = sum(1 for t in tasks if t.status.value == "done")
    pending_count = sum(1 for t in tasks if t.status.value == "pending")
    skipped_count = sum(1 for t in tasks if t.status.value == "skipped")

    context_lines = [
        f"Date: {today.isoformat()}",
        f"Tasks: {len(tasks)} total — {done_count} done, {pending_count} pending, {skipped_count} skipped",
        f"Max tasks per day: {result.get('max_tasks_per_day', 'N/A')}",
        "",
    ]

    # Group tasks by plan → milestone
    tasks_by_plan: dict = {}
    for t in tasks:
        tasks_by_plan.setdefault(t.plan_id, []).append(t)

    for pid, plan_tasks in tasks_by_plan.items():
        plan = plans_by_id.get(pid)
        plan_label = plan.title if plan else "Unknown Plan"
        plan_status = plan.status.value if plan else "unknown"
        context_lines.append(f"Plan: {plan_label} (status: {plan_status})")

        # Sub-group by milestone
        by_ms: dict = {}
        for t in plan_tasks:
            mid = t.milestone_id or "__no_ms__"
            by_ms.setdefault(mid, []).append(t)

        for mid, ms_tasks in by_ms.items():
            ms = milestones_by_id.get(mid) if mid != "__no_ms__" else None
            ms_label = ms.title if ms else "No milestone"
            context_lines.append(f"  Milestone: {ms_label}")
            for t in ms_tasks:
                status_str = t.status.value
                duration_str = f" ({t.duration_minutes}min)" if t.duration_minutes else ""
                carry_str = f" [carry-over ×{t.carry_over_count}]" if t.carry_over_count > 0 else ""
                struggling_str = " ⚠ struggling" if t.struggling else ""
                context_lines.append(f"    - {t.title} [{status_str}]{duration_str}{carry_str}{struggling_str}")
        context_lines.append("")

    context_block = "\n".join(context_lines)

    # ── If a specific task is selected, append task detail context ────────────
    task_context_block = ""
    if payload.task_id:
        try:
            task = adaptive_store.get_task(UUID(payload.task_id))
            if task and task.detail_json:
                d = task.detail_json
                task_lines = [f"SELECTED TASK: {task.title} [status: {task.status.value}]"]
                if d.get("what_is_this"):
                    task_lines.append(f"  What is this: {d['what_is_this']}")
                if d.get("why_it_matters"):
                    task_lines.append(f"  Why it matters: {d['why_it_matters']}")
                if d.get("how_to_do_it"):
                    for step in d["how_to_do_it"]:
                        task_lines.append(f"  Step {step.get('step','?')}: {step.get('instruction','')}")
                if d.get("resources"):
                    for r in d["resources"]:
                        task_lines.append(f"  Resource [{r.get('type','link')}]: {r.get('title','')} — {r.get('description','')}")
                if d.get("expert_tip"):
                    task_lines.append(f"  Expert tip: {d['expert_tip']}")
                if d.get("todays_example"):
                    task_lines.append(f"  Today's example: {d['todays_example']}")
                if d.get("estimated_difficulty"):
                    task_lines.append(f"  Estimated difficulty: {d['estimated_difficulty']}")
                task_context_block = "\n\n=== SELECTED TASK DETAIL ===\n" + "\n".join(task_lines)
        except Exception as e:
            logger.warning("today_task_context_fetch_error=%s", e)

    full_system = f"{TODAY_CHAT_SYSTEM_PROMPT}\n\n=== TODAY'S SCHEDULE ===\n{context_block}{task_context_block}"
    prompt = payload.message

    try:
        content = chatResponse(prompt, system=full_system)
    except Exception as exc:
        logger.exception("Today chat LLM call failed")
        return PlanChatResponse(reply=f"Sorry, I couldn't process that: {exc}", actions=[])

    # Parse actions from ```plan-actions``` code fences
    actions: list[PlanChatAction] = []
    reply_text = content
    action_match = re.search(r"```plan-actions\s*\n([\s\S]*?)\n```", content)
    if action_match:
        try:
            action_json = json.loads(action_match.group(1))
            if isinstance(action_json, list):
                for a in action_json:
                    actions.append(PlanChatAction(
                        action=a.get("action", ""),
                        target_id=a.get("target_id"),
                        params=a.get("params", {}),
                    ))
            elif isinstance(action_json, dict):
                actions.append(PlanChatAction(
                    action=action_json.get("action", ""),
                    target_id=action_json.get("target_id"),
                    params=action_json.get("params", {}),
                ))
        except json.JSONDecodeError:
            pass
        reply_text = content[:action_match.start()] + content[action_match.end():]
        reply_text = reply_text.strip()

    return PlanChatResponse(reply=reply_text, actions=actions)


# ── Create Plan from Memory ───────────────────────────────────────────────────

@router.post("/create-plan", response_model=CreatePlanResponse)
@limit_10_per_minute  # Plan generation is expensive when slowapi is available
async def create_plan_from_memory(
    request: Request,  # Required by slowapi
    payload: CreatePlanRequest,
    user_id: UUID = Depends(get_current_user),
):
    result = plan_generator_service.create_plan_from_memory(user_id, payload.memory_id)
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])

    plan = result["plan"]
    milestone_results = result["milestones"]
    total_tasks = sum(len(ms["tasks"]) for ms in milestone_results)

    milestone_responses = []
    for ms_data in milestone_results:
        ms = ms_data["milestone"]
        tasks = ms_data["tasks"]
        milestone_responses.append(_milestone_to_response(ms, tasks))

    return CreatePlanResponse(
        plan=PlanResponse(
            id=plan.id,
            goal_id=plan.goal_id,
            memory_id=getattr(plan, 'memory_id', None),
            user_id=plan.user_id,
            title=plan.title,
            status=plan.status,
            priority=plan.priority,
            intensity=plan.intensity,
            created_at=plan.created_at,
            updated_at=plan.updated_at,
        ),
        milestones=milestone_responses,
        task_count=total_tasks,
    )


# ── Memory Extraction ──────────────────────────────────────────────────────────

@router.post("/extract-memory", response_model=ExtractMemoryResponse)
async def extract_memory(
    payload: ExtractMemoryRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Legacy endpoint — same hybrid extraction as /memory/extract."""
    conversation = [{"role": "user", "content": payload.conversation}]
    result = await extract_and_save(str(user_id), conversation, adaptive_store)
    all_items = result.all_items
    return ExtractMemoryResponse(
        extracted=[
            ExtractedField(key=item["key"], value=item["value"], id=item.get("id"))
            for item in all_items
        ],
        count=len(all_items),
    )


# ── Adjustment Suggestions ─────────────────────────────────────────────────────

@router.get("/adjustments", response_model=list[AdjustmentSuggestionResponse])
async def list_adjustments(
    user_id: UUID = Depends(get_current_user),
):
    suggestions = adaptive_store.list_pending_suggestions(user_id)
    results = []
    for s in suggestions:
        # If suggestion has no tasks yet, try generating via LLM
        if not s.suggested_tasks:
            generated = llm_adjuster_service.generate_suggestions(s.id)
            if generated:
                # Re-fetch after LLM fills in
                s = adaptive_store.get_suggestion(s.id)
        results.append(_suggestion_to_response(s))
    return results


@router.post("/adjustments/{suggestion_id}/approve", response_model=AdjustmentSuggestionResponse)
async def approve_adjustment(
    suggestion_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    suggestion = adaptive_store.get_suggestion(suggestion_id)
    if suggestion is None or suggestion.user_id != user_id:
        raise HTTPException(status_code=404, detail="Suggestion not found")
    if suggestion.status != AdjustmentStatus.pending:
        raise HTTPException(status_code=400, detail="Suggestion is not pending")

    success = llm_adjuster_service.apply_approved_suggestion(suggestion_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to apply suggestion")
    updated = adaptive_store.get_suggestion(suggestion_id)
    return _suggestion_to_response(updated)


@router.post("/adjustments/{suggestion_id}/dismiss", response_model=AdjustmentSuggestionResponse)
async def dismiss_adjustment(
    suggestion_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    suggestion = adaptive_store.get_suggestion(suggestion_id)
    if suggestion is None or suggestion.user_id != user_id:
        raise HTTPException(status_code=404, detail="Suggestion not found")
    if suggestion.status != AdjustmentStatus.pending:
        raise HTTPException(status_code=400, detail="Suggestion is not pending")

    adaptive_store.resolve_suggestion(suggestion_id, AdjustmentStatus.dismissed)
    updated = adaptive_store.get_suggestion(suggestion_id)
    return _suggestion_to_response(updated)


# ── Milestones ─────────────────────────────────────────────────────────────────

@router.get("/plans/{plan_id}/milestones", response_model=list[MilestoneResponse])
async def list_milestones(
    plan_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    milestones = adaptive_store.get_milestones_for_plan(user_id, plan_id)
    results = []
    for ms in milestones:
        tasks = adaptive_store.get_tasks_for_milestone(user_id, ms.id)
        results.append(_milestone_to_response(ms, tasks))
    return results


@router.post("/plans/{plan_id}/milestones", response_model=MilestoneResponse)
async def create_milestone(
    plan_id: UUID,
    payload: MilestoneCreate,
    user_id: UUID = Depends(get_current_user),
):
    plan = adaptive_store.get_plan(plan_id)
    if plan is None or (plan.user_id and plan.user_id != user_id):
        raise HTTPException(status_code=404, detail="Plan not found")
    ms = adaptive_store.create_milestone(user_id, plan_id, payload.model_dump())
    return _milestone_to_response(ms, [])


@router.patch("/milestones/{milestone_id}", response_model=MilestoneResponse)
async def update_milestone(
    milestone_id: UUID,
    payload: MilestoneUpdate,
    user_id: UUID = Depends(get_current_user),
):
    ms = adaptive_store.update_milestone(user_id, milestone_id, payload.model_dump(exclude_unset=True))
    if ms is None:
        raise HTTPException(status_code=404, detail="Milestone not found")
    tasks = adaptive_store.get_tasks_for_milestone(user_id, ms.id)
    return _milestone_to_response(ms, tasks)


@router.get("/milestones/{milestone_id}/check-completion")
async def check_milestone_completion(
    milestone_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    is_complete = adaptive_store.check_milestone_completion(user_id, milestone_id)
    if not is_complete:
        return {"completed": False, "next_milestone": None}
    # Mark milestone as completed
    ms = adaptive_store.update_milestone(user_id, milestone_id, {"status": MilestoneStatus.completed})
    if ms is None:
        raise HTTPException(status_code=404, detail="Milestone not found")
    # Activate the next locked milestone in the same plan
    next_ms = adaptive_store.activate_next_milestone(user_id, ms.plan_id)
    # Auto-generate tasks for the newly activated milestone
    if next_ms:
        try:
            await generate_for_milestone(str(next_ms.id), str(user_id), adaptive_store)
        except Exception as e:
            logger.warning("Task generation for milestone %s failed: %s", next_ms.id, e)
    # Trigger deep review on milestone completion
    try:
        deep_review_service.on_milestone_completed(user_id, milestone_id)
    except Exception as e:
        logger.warning("Deep review trigger on milestone failed: %s", e)
    return {
        "completed": True,
        "milestone": _milestone_to_response(ms, []),
        "next_milestone": _milestone_to_response(next_ms, []) if next_ms else None,
    }


@router.get("/milestones/{milestone_id}/insight", response_model=MilestoneInsightResponse)
async def get_milestone_insight(
    milestone_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    ms_res = (
        adaptive_store.client.table("milestones")
        .select()
        .eq("id", str(milestone_id))
        .eq("user_id", str(user_id))
        .limit(1)
        .execute()
    )
    if not ms_res or not ms_res[1]:
        raise HTTPException(status_code=404, detail="Milestone not found")
    ms_row = ms_res[1][0]

    # ── Cache check: if insight_json already stored, return it immediately ──
    cached_insight = adaptive_store._safe_json_dict(ms_row.get("insight_json"))
    if cached_insight:
        return MilestoneInsightResponse(
            milestone_id=milestone_id,
            insight=cached_insight,
            raw=None,
            generated=False,
        )

    # ── No cache — generate via LLM ──
    tasks = adaptive_store.get_tasks_for_milestone(user_id, milestone_id)

    milestone_snapshot = {
        "id": ms_row.get("id"),
        "plan_id": ms_row.get("plan_id"),
        "title": ms_row.get("title"),
        "description": ms_row.get("description"),
        "status": ms_row.get("status"),
        "order_index": ms_row.get("order_index"),
    }
    task_snapshots = [
        {
            "id": str(t.id),
            "title": t.title,
            "status": t.status.value,
            "due_date": t.due_date.isoformat() if t.due_date else None,
            "duration_minutes": t.duration_minutes,
        }
        for t in tasks[:12]
    ]

    prompt = MILESTONE_INSIGHT_PROMPT.format(
        milestone=json.dumps(milestone_snapshot, ensure_ascii=False),
        tasks=json.dumps(task_snapshots, ensure_ascii=False),
    )

    content = ""
    parsed, raw = None, ""
    try:
        content = chatResponse(prompt)
        parsed, raw = _try_parse_json(content)
        if parsed is None:
            retry_prompt = (
                "Return valid JSON only. Do not include any markdown, code fences, or extra text. "
                "The response must be a single JSON object.\n\n" + prompt
            )
            content2 = chatResponse(retry_prompt)
            parsed, raw = _try_parse_json(content2)
            content = content2
    except Exception as exc:
        parsed = None
        raw = str(exc)

    if parsed is None:
        return MilestoneInsightResponse(
            milestone_id=milestone_id,
            insight={"raw": _strip_code_fences(content) if content else ""},
            raw=_strip_code_fences(content) if content else raw,
            generated=True,
        )

    # Cache the successfully parsed insight on the milestone record
    adaptive_store.update_milestone_insight_json(milestone_id, parsed)

    return MilestoneInsightResponse(
        milestone_id=milestone_id,
        insight=parsed,
        raw=None,
        generated=True,
    )


# ── Admin / Rollback ────────────────────────────────────────────────────────────

@router.post("/admin/rollback-webhook")
async def rollback_webhook(
    user_id: UUID = Depends(get_current_user),
):
    """Emergency rollback: disables V2 endpoints server-side.

    When triggered, all /v2 endpoints will fall back to their V1
    implementations. This is the server-side kill-switch that complements
    the client-side feature flag.
    """
    global _v2_enabled
    previous = _v2_enabled
    _v2_enabled = False
    logger.warning("ROLLBACK WEBHOOK TRIGGERED by user %s — V2 disabled (was %s)", user_id, previous)
    return {"v2_enabled": False, "previous": previous, "message": "V2 endpoints disabled. All /v2 routes now fall back to V1."}


@router.post("/admin/enable-v2")
async def enable_v2(
    user_id: UUID = Depends(get_current_user),
):
    """Re-enable V2 endpoints after a rollback."""
    global _v2_enabled
    previous = _v2_enabled
    _v2_enabled = True
    logger.info("V2 RE-ENABLED by user %s (was %s)", user_id, previous)
    return {"v2_enabled": True, "previous": previous, "message": "V2 endpoints re-enabled."}


@router.get("/admin/v2-status")
async def v2_status(
    user_id: UUID = Depends(get_current_user),
):
    """Check the current state of the server-side V2 feature flag."""
    return {"v2_enabled": _v2_enabled}


# ── Event Triggers / Proactive Nudges ─────────────────────────────────────────

@router.post("/triggers/check")
async def check_triggers(
    task_id: UUID | None = None,
    user_id: UUID = Depends(get_current_user),
):
    """Run all real-time event triggers for the user. Returns list of nudges."""
    nudges = run_all_triggers(user_id, task_id=task_id)
    return {"nudges": nudges}


# ── Training Data Collection (Phase 1b) ──────────────────────────────────────

@router.post("/collect-prediction-data")
async def collect_prediction_data(
    task_id: UUID,
    scheduled_hour: int | None = None,
    task_category: str | None = None,
    day_of_week: int | None = None,
    actual_completed: bool | None = None,
    duration_seconds: int | None = None,
    user_id: UUID = Depends(get_current_user),
):
    """Collect task completion prediction data for on-device ML training."""
    data = {
        "user_id": str(user_id),
        "task_id": str(task_id),
    }
    if scheduled_hour is not None:
        data["scheduled_hour"] = scheduled_hour
    if task_category is not None:
        data["task_category"] = task_category
    if day_of_week is not None:
        data["day_of_week"] = day_of_week
    if actual_completed is not None:
        data["actual_completed"] = actual_completed
    if duration_seconds is not None:
        data["duration_seconds"] = duration_seconds

    res = adaptive_store.client.table("task_completion_predictions").insert(data).execute()
    return {"status": "recorded"}


@router.get("/model-weights")
async def get_model_weights(
    user_id: UUID = Depends(get_current_user),
):
    """Stub endpoint for on-device ML model weights. Returns placeholder."""
    return {
        "version": "0.1.0",
        "weights": {},
        "features": ["scheduled_hour", "day_of_week", "task_category", "carry_over_count"],
        "message": "Model weights not yet trained. Collect more data first.",
    }


# ── Daily Summary (instant read, no LLM) ─────────────────────────────────────────

@router.get("/daily-summary", response_model=DailySummaryResponse | None)
async def get_daily_summary(
    for_date: date | None = None,
    user_id: UUID = Depends(get_current_user),
):
    """Get cached daily summary for a date. Returns None if no summary exists yet."""
    target = for_date or date.today()
    summary = adaptive_store.get_daily_summary(user_id, target)
    if summary is None:
        return None
    return DailySummaryResponse(
        id=summary.id,
        user_id=summary.user_id,
        date=summary.date,
        summary_text=summary.summary_text,
        stats_json=summary.stats_json,
        created_at=summary.created_at,
    )


# ── Episodic Memories ─────────────────────────────────────────────────────────

@router.get("/episodic-memories", response_model=list[EpisodicMemoryResponse])
async def list_episodic_memories(
    limit: int = 20,
    user_id: UUID = Depends(get_current_user),
):
    mems = adaptive_store.list_episodic_memories(user_id, limit=limit)
    return [
        EpisodicMemoryResponse(
            id=m.id,
            user_id=m.user_id,
            type=m.type,
            content=m.content,
            context_json=m.context_json,
            learned_rule=m.learned_rule,
            created_at=m.created_at,
        )
        for m in mems
    ]


# ── App-Open Adaptation (replaces midnight cron) ──────────────────────────────

@router.post("/adapt/on-open")
async def adapt_on_app_open(
    user_id: UUID = Depends(get_current_user),
):
    """App-open adaptation: catches up on overdue tasks, rebalances workload,
    runs proactive triggers. The system adapts the moment the user engages.
    """
    result = on_app_open(user_id)
    return {"status": "adapted", **result}


@router.post("/adapt/on-event")
async def adapt_on_event(
    event_type: str,
    task_id: UUID | None = None,
    user_id: UUID = Depends(get_current_user),
):
    """Manual trigger for the adaptation engine on a specific event.
    Primarily for debugging / manual override.
    """
    from backend.adaptive.services.adaptation_engine import adapt_on_event as _adapt
    context = {}
    if task_id:
        context["task_id"] = str(task_id)
    result = _adapt(user_id, event_type, context)
    return result


# ── Deep Review (trigger-based, replaces Sunday cron) ─────────────────────────

@router.post("/deep-review/check")
async def trigger_deep_review_check(
    user_id: UUID = Depends(get_current_user),
):
    """Check failure thresholds and trigger a deep review if needed.
    Also triggered automatically on milestone completion and task skips.
    """
    result = deep_review_service.check_and_trigger(user_id)
    if result is None:
        return {"triggered": False, "reason": "No failure threshold reached"}
    return {"triggered": True, "review": result}


@router.post("/deep-review/milestone/{milestone_id}")
async def trigger_deep_review_milestone(
    milestone_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Manually trigger a deep review after a milestone completion.
    This is also triggered automatically when a milestone is completed.
    """
    result = deep_review_service.on_milestone_completed(user_id, milestone_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Milestone not found")
    return {"triggered": True, "review": result}


# ── Helpers ────────────────────────────────────────────────────────────────────


def _daily_schedule_response(result: dict, adapt_result: dict | None = None) -> DailyTasksResponse:
    tasks = result["tasks"]
    plan_ids = {t.plan_id for t in tasks}
    milestone_ids = {t.milestone_id for t in tasks if t.milestone_id}

    plans_by_id = {}
    plans_metadata: dict[str, DailyPlanMetadata] = {}
    for plan_id in plan_ids:
        plan = adaptive_store.get_plan(plan_id)
        if plan:
            plans_by_id[plan_id] = plan
            plans_metadata[str(plan_id)] = DailyPlanMetadata(
                id=plan.id,
                title=plan.title,
                priority=plan.priority,
                status=plan.status,
            )

    milestones_metadata: dict[str, DailyMilestoneMetadata] = {}
    for plan_id, plan in plans_by_id.items():
        if not plan.user_id:
            continue
        for ms in adaptive_store.get_milestones_for_plan(plan.user_id, plan_id):
            if ms.id in milestone_ids:
                milestones_metadata[str(ms.id)] = DailyMilestoneMetadata(
                    id=ms.id,
                    plan_id=ms.plan_id,
                    title=ms.title,
                    status=ms.status,
                    order_index=ms.order_index,
                )

    task_plan_names = {
        str(t.id): plans_metadata.get(str(t.plan_id)).title
        for t in tasks
        if plans_metadata.get(str(t.plan_id))
    }
    task_milestone_titles = {
        str(t.id): milestones_metadata.get(str(t.milestone_id)).title
        for t in tasks
        if t.milestone_id and milestones_metadata.get(str(t.milestone_id))
    }

    return DailyTasksResponse(
        date=result["date"],
        tasks=_tasks_with_indices(tasks),
        total_available=result["total_available"],
        selected_count=result["selected_count"],
        max_tasks_per_day=result["max_tasks_per_day"],
        selected_task_ids=[t.id for t in tasks],
        plans_metadata=plans_metadata,
        milestones_metadata=milestones_metadata,
        metadata={
            "adaptation": adapt_result or {},
            "plans_queried": result.get("plans_queried", 0),
            "plan_names": task_plan_names,
            "milestone_titles": task_milestone_titles,
            "plans_working_day": result.get("plans_working_day", {}),
            "daily_limit": result.get("daily_limit", result["max_tasks_per_day"]),
            "extra_task_ids": result.get("extra_task_ids", []),
            "locked": result.get("locked", False),
        },
    )

def _plan_to_response(p, progress_pct: float = 0.0, total_tasks: int = 0, remaining_tasks: int = 0) -> PlanResponse:
    return PlanResponse(
        id=p.id,
        goal_id=p.goal_id,
        memory_id=getattr(p, 'memory_id', None),
        user_id=p.user_id,
        title=p.title,
        status=p.status,
        priority=p.priority,
        intensity=p.intensity,
        duration_days=getattr(p, 'duration_days', None),
        schedule_prefs=getattr(p, 'schedule_prefs', None),
        progress_pct=progress_pct,
        total_tasks=total_tasks,
        remaining_tasks=remaining_tasks,
        created_at=p.created_at,
        updated_at=p.updated_at,
    )


def _task_to_response(t, task_index: int = 0, subtask_counts: dict[str, int] | None = None) -> TaskResponse:
    subtask_counts = subtask_counts or adaptive_store.count_subtasks_by_task(t.id)
    return TaskResponse(
        id=t.id,
        plan_id=t.plan_id,
        title=t.title,
        description=t.description,
        due_date=t.due_date,
        status=t.status,
        priority=t.priority,
        difficulty=t.difficulty,
        parent_id=t.parent_id,
        carry_over_count=t.carry_over_count,
        milestone_id=t.milestone_id,
        order_index=t.order_index,
        task_index=task_index,
        subtask_count=subtask_counts["total"],
        completed_subtask_count=subtask_counts["completed"],
        has_subtasks=subtask_counts["total"] > 0,
        duration_minutes=t.duration_minutes,
        detail_json=t.detail_json,
        rescheduled_from=getattr(t, 'rescheduled_from', None),
        struggling=getattr(t, 'struggling', False),
        skip_reason=getattr(t, 'skip_reason', None),
        skipped_at=getattr(t, 'skipped_at', None),
        created_at=t.created_at,
        updated_at=t.updated_at,
    )


def _subtask_to_response(s) -> SubtaskResponse:
    return SubtaskResponse(
        id=s.id,
        task_id=s.task_id,
        title=s.title,
        completed=s.completed,
        order_index=s.order_index,
        created_at=s.created_at,
        updated_at=s.updated_at,
    )


def _require_user_task(task_id: UUID, user_id: UUID):
    task = adaptive_store.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    plan = adaptive_store.get_plan(task.plan_id)
    if plan is None or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


def _tasks_with_indices(tasks: list) -> list[TaskResponse]:
    """Calculate task_index for each task based on its position in the plan roadmap."""
    if not tasks:
        return []
    subtask_counts_by_id = adaptive_store.count_subtasks_batch([t.id for t in tasks])
    
    # Group tasks by plan
    by_plan: dict[UUID, list] = {}
    for t in tasks:
        by_plan.setdefault(t.plan_id, []).append(t)

    # For each plan, get all milestones and that plan, then calculate indices
    plan_task_indices: dict[UUID, dict[UUID, int]] = {}  # plan_id -> {task_id -> index}
    for plan_id, plan_tasks in by_plan.items():
        if not plan_tasks:
            continue
        # Get the plan to access user_id
        plan = adaptive_store.get_plan(plan_id)
        # Get all tasks for this plan to calculate proper indices
        all_plan_tasks = adaptive_store.get_tasks_for_plan(plan_id)
        
        logger.info(f"_tasks_with_indices: plan_id={plan_id}, all_tasks={len(all_plan_tasks)}, input_tasks={len(plan_tasks)}")
        
        if not all_plan_tasks:
            # Fallback: use input tasks directly with simple ordering
            logger.warning(f"_tasks_with_indices: no tasks found for plan {plan_id}, using input tasks")
            all_plan_tasks = plan_tasks
        
        # Group by milestone
        by_milestone: dict[UUID | None, list] = {}
        for pt in all_plan_tasks:
            by_milestone.setdefault(pt.milestone_id, []).append(pt)

        # Get milestone order
        milestone_order: dict[UUID | None, int] = {}
        if plan and plan.user_id:
            milestones = adaptive_store.get_milestones_for_plan(plan.user_id, plan_id)
            for i, ms in enumerate(sorted(milestones, key=lambda m: m.order_index)):
                milestone_order[ms.id] = i
        
        logger.info(f"_tasks_with_indices: milestones={len(milestone_order)}, by_milestone_groups={len(by_milestone)}")

        # Calculate global task index
        task_index_map = {}
        global_idx = 1
        # Sort milestones by order (tasks without milestone go first with order -1)
        sorted_milestone_ids = sorted(by_milestone.keys(), key=lambda mid: milestone_order.get(mid, 999) if mid else -1)
        for mid in sorted_milestone_ids:
            ms_tasks = sorted(by_milestone[mid], key=lambda t: t.order_index)
            for pt in ms_tasks:
                task_index_map[pt.id] = global_idx
                global_idx += 1
        plan_task_indices[plan_id] = task_index_map
        
        logger.info(f"_tasks_with_indices: calculated {len(task_index_map)} indices for plan {plan_id}")

    # Build responses with calculated indices
    result = []
    for t in tasks:
        idx = plan_task_indices.get(t.plan_id, {}).get(t.id, 0)
        if idx == 0:
            logger.warning(f"_tasks_with_indices: task {t.id} has no index in plan {t.plan_id}")
        result.append(_task_to_response(t, idx, subtask_counts_by_id.get(str(t.id))))
    return result


def _milestone_to_response(ms, tasks=None) -> MilestoneResponse:
    return MilestoneResponse(
        id=ms.id,
        plan_id=ms.plan_id,
        user_id=ms.user_id,
        title=ms.title,
        description=ms.description,
        order_index=ms.order_index,
        status=ms.status,
        suggested_days=getattr(ms, 'suggested_days', None),
        outcome=getattr(ms, 'outcome', None),
        tasks=_tasks_with_indices(tasks or []),
        created_at=ms.created_at,
        updated_at=ms.updated_at,
    )


def _memory_to_response(m) -> MemoryResponse:
    return MemoryResponse(
        id=m.id,
        user_id=m.user_id,
        key=m.key,
        value=m.value,
        source=m.source,
        importance=getattr(m, "importance", 0),
        confidence=getattr(m, "confidence", 0.5),
        user_visible=getattr(m, "user_visible", True),
        goal_id=m.goal_id,
        created_at=m.created_at,
        updated_at=m.updated_at,
    )


def _suggestion_to_response(s) -> AdjustmentSuggestionResponse:
    return AdjustmentSuggestionResponse(
        id=s.id,
        plan_id=s.plan_id,
        reason=s.reason,
        suggested_tasks=s.suggested_tasks,
        status=s.status,
        created_at=s.created_at,
        resolved_at=s.resolved_at,
    )


# ── Task History ───────────────────────────────────────────────────────────────

@router.get("/history", response_model=TaskHistoryListResponse)
async def get_task_history(
    plan_id: UUID | None = None,
    search: str | None = None,
    limit: int = 100,
    user_id: UUID = Depends(get_current_user),
):
    """Get task completion history for the current user.

    Results are ordered by completion time, most recent first.
    Can be filtered by plan_id and search query.
    """
    history = adaptive_store.list_task_history(
        user_id=user_id,
        plan_id=plan_id,
        search_query=search,
        limit=limit,
    )
    return TaskHistoryListResponse(
        history=[_history_to_response(h) for h in history],
        total=len(history),
    )


def _history_to_response(h) -> TaskHistoryResponse:
    return TaskHistoryResponse(
        id=h.id,
        user_id=h.user_id,
        task_id=h.task_id,
        task_index=h.task_index,
        task_name=h.task_name,
        milestone_id=h.milestone_id,
        milestone_name=h.milestone_name,
        plan_id=h.plan_id,
        plan_name=h.plan_name,
        plan_completed=h.plan_completed,
        working_day_index=h.working_day_index,
        calendar_date=h.calendar_date,
        completed_at=h.completed_at,
        created_at=h.created_at,
    )
