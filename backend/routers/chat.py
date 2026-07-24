import asyncio
import json
import logging
import re

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from typing import Any
from uuid import UUID
try:
    from slowapi import Limiter
    from slowapi.util import get_remote_address
except ImportError:
    Limiter = None
    get_remote_address = None

from backend.auth import get_current_user
from backend.lib.llm_client import asend_chat, asend_chat_guided, LLMProviderError
from backend.adaptive.db import adaptive_store
from backend.adaptive.models import PlanStatus, TaskStatus
from backend.adaptive.schemas import PlanChatAction
from backend.adaptive.services.adjuster import adjuster_service

# Rate limiter for chat endpoints (expensive LLM calls)
if Limiter and get_remote_address:
    limiter = Limiter(key_func=get_remote_address)
    limit_30_per_minute = limiter.limit("30/minute")
else:
    limiter = None

    def limit_30_per_minute(func):
        return func

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chat", tags=["chat"])

class ChatRequest(BaseModel):
    message: str
    mode: str | None = "chat"          # ignored for now; kept for frontend compatibility
    source: str | None = "chat"        # "chat" or "guided"
    conversation_id: str | None = None # persist messages to this conversation
    history: list[dict] | None = None  # optional conversation history for context
    session_context: dict = {}         # frontend session context for context builder


class ChatResponse(BaseModel):
    reply: str
    route_type: str | None = None
    actions: list[PlanChatAction] = []
    mentioned_plan: str | None = None  # plan title if a plan was detected

# System prompt for guided AI interactions
GUIDED_SYSTEM_PROMPT = """You are an AI planning assistant. Based on the user query, respond in a structured, helpful way. If the query is about learning or planning, provide step-by-step roadmap or actionable plan.

For career-related queries: Respond with structured career options and roadmap.
For job-related queries: Respond with job plan and resume/interview advice.
For learning/roadmap queries: Generate roadmap with phases and tasks.
For quiz/test queries: Generate quiz questions with MCQ or short questions format.

Response format for learning/roadmap:
{
  "title": "Roadmap Title",
  "phases": [
    {
      "name": "Phase Name",
      "tasks": ["Task 1", "Task 2", "Task 3"]
    }
  ]
}

Response format for quiz:
{
  "questions": [
    {
      "question": "Question text",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "answer": "A"
    }
  ]
}

Always provide helpful, actionable responses."""

def _route_query(message: str) -> str:
    """Determine routing based on message content."""
    msg_lower = message.lower()
    
    if any(word in msg_lower for word in ["career", "career path", "career option"]):
        return "career"
    elif any(word in msg_lower for word in ["job", "resume", "interview", "hiring"]):
        return "job"
    elif any(word in msg_lower for word in ["learn", "learning", "roadmap", "topic", "plan", "7-day", "7 day"]):
        return "learn"
    elif any(word in msg_lower for word in ["test", "quiz", "practice", "knowledge", "skill level", "evaluate"]):
        return "test"
    else:
        return "general"

# ── Intent classification prompt ──────────────────────────────────────────────
INTENT_CLASSIFY_PROMPT = """You are a scheduling intent classifier. Given the user's latest message, classify it into exactly ONE of these intents:

- "busy_today": User says they're busy, overwhelmed, need a lighter schedule, too much to do today
- "skip_task": User wants to skip a specific task (mention a task name)
- "pause_plan": User wants to pause a plan entirely (mention a plan name)
- "none": No adjustment intent — general conversation

Respond with ONLY a JSON object: {"intent": "<intent>", "task_name": "<extracted task name or null>", "plan_name": "<extracted plan name or null>"}

Do not include any other text."""


async def _classify_intent(message: str, user_id: UUID) -> dict:
    """Lightweight LLM call to classify user intent. Returns dict with intent, task_name, plan_name."""
    try:
        raw = await asend_chat(user_id, [
            {"role": "system", "content": INTENT_CLASSIFY_PROMPT},
            {"role": "user", "content": message},
        ])
        json_match = re.search(r'\{[\s\S]*\}', raw)
        if json_match:
            return json.loads(json_match.group())
    except Exception as e:
        logger.warning("intent_classify_error=%s", e)
    return {"intent": "none", "task_name": None, "plan_name": None}


async def _handle_adjustment(user_id: UUID, intent_data: dict) -> str | None:
    """Process a detected adjustment intent. Returns a note to append to the reply, or None."""
    intent = intent_data.get("intent", "none")
    if intent == "none":
        return None

    try:
        if intent == "busy_today":
            rescheduled = await asyncio.to_thread(adjuster_service.handle_busy, user_id)
            count = len(rescheduled)
            if count > 0:
                return f"Got it — I've lightened today's schedule. {count} task{'s' if count != 1 else ''} moved to tomorrow."
            return "I checked your schedule — there are no pending tasks to reschedule today."

        elif intent == "skip_task":
            task_name = intent_data.get("task_name")
            if not task_name:
                return None
            # Find matching task by title (fuzzy match)
            from datetime import date as _date
            today_tasks = await asyncio.to_thread(adaptive_store.get_tasks_for_date, user_id, _date.today())
            matching = [t for t in today_tasks if task_name.lower() in t.title.lower()]
            if matching:
                task = matching[0]
                await asyncio.to_thread(adjuster_service.handle_skip, user_id, task.id)
                return f"Skipped '{task.title}' — it's been moved to tomorrow."
            return f"I couldn't find a task matching '{task_name}' in today's schedule."

        elif intent == "pause_plan":
            plan_name = intent_data.get("plan_name")
            if not plan_name:
                return None
            # Find matching plan
            all_plans = await asyncio.to_thread(adaptive_store.list_all_plans, user_id)
            matching = [p for p in all_plans if p.title and plan_name.lower() in p.title.lower() and p.status == PlanStatus.active]
            if matching:
                plan = matching[0]
                await asyncio.to_thread(adaptive_store.update_plan, plan.id, status=PlanStatus.paused)
                return f"Paused plan '{plan.title}'. Its tasks won't appear in your schedule until you resume it."
            return f"I couldn't find an active plan matching '{plan_name}'."
    except Exception as e:
        logger.warning("adjustment_error=%s", e)
        return None

    return None


# ── Plan mention detection ──────────────────────────────────────────────────────

PLAN_ACTIONS_SYSTEM_PROMPT = """You are Life Agent — an AI planning assistant. The user has mentioned a specific plan, and you now have full context about it.

When the user asks for changes, respond with a JSON block wrapped in ```plan-actions``` code fences containing an array of action objects. Each action has:
- "action": one of "reframe_milestone", "rename_milestone", "add_task", "remove_task", "reorder_task", "change_next_task", "split_milestone", "skip_task", "mark_blocked"
- "target_id": the UUID of the milestone or task being modified (if applicable)
- "params": object with action-specific parameters (e.g. {"title": "new name"}, {"description": "..."})

You may include explanatory text BEFORE the code fence. If no actions are needed, just respond with helpful text and no code fence.

Always be specific — reference actual milestone and task names from the plan context."""


async def _detect_plan_mention(message: str, user_id: UUID) -> tuple[str | None, str | None]:
    """Check if the user's message mentions one of their plans.
    
    Returns (plan_id, plan_title) if a match is found, else (None, None).
    Uses fuzzy matching: plan title words must appear in the message.
    """
    msg_lower = message.lower()
    try:
        plans = await asyncio.to_thread(adaptive_store.list_all_plans, user_id)
    except Exception:
        return None, None

    best_match = None
    best_score = 0

    for plan in plans:
        if not plan.title:
            continue
        title_lower = plan.title.lower()
        title_words = [w for w in title_lower.split() if len(w) > 2]

        # Exact substring match — highest priority
        if title_lower in msg_lower:
            return str(plan.id), plan.title

        # Word overlap score
        matching = sum(1 for w in title_words if w in msg_lower)
        score = matching / max(len(title_words), 1)

        if score > best_score and score >= 0.5:
            best_score = score
            best_match = (str(plan.id), plan.title)

    if best_match and best_score >= 0.5:
        return best_match
    return None, None


async def _build_plan_context_block(plan_id: str, user_id: UUID) -> str | None:
    """Build a plan context summary block for the system prompt.
    
    Returns the context string, or None on error.
    """
    try:
        plan = await asyncio.to_thread(adaptive_store.get_plan, UUID(plan_id))
        if not plan:
            return None

        milestones = await asyncio.to_thread(adaptive_store.get_milestones_for_plan, user_id, UUID(plan_id))
        lines = [f"Plan: {plan.title} (status: {plan.status.value})"]
        # Fetch tasks for all milestones in parallel
        tasks_coros = [asyncio.to_thread(adaptive_store.get_tasks_for_milestone, user_id, ms.id) for ms in milestones]
        tasks_results = await asyncio.gather(*tasks_coros)
        for ms, tasks in zip(milestones, tasks_results):
            done = sum(1 for t in tasks if t.status.value == "done")
            lines.append(
                f"  Milestone {ms.order_index + 1}: {ms.title} [{ms.status.value}] — {done}/{len(tasks)} tasks done"
            )
            for t in tasks[:8]:
                lines.append(f"    - {t.title} [{t.status.value}]")
        return "\n".join(lines)
    except Exception as e:
        logger.warning("build_plan_context_error=%s", e)
        return None


def _parse_plan_actions(content: str) -> tuple[list[PlanChatAction], str]:
    """Parse ```plan-actions``` code fences from LLM response.
    
    Returns (actions_list, cleaned_reply_text).
    """
    actions: list[PlanChatAction] = []
    reply_text = content
    action_match = re.search(r"```plan-actions\s*\n([\s\S]*?)\n```", content)
    if action_match:
        try:
            action_json = json.loads(action_match.group(1))
            items = action_json if isinstance(action_json, list) else [action_json]
            for a in items:
                actions.append(PlanChatAction(
                    action=a.get("action", ""),
                    target_id=a.get("target_id"),
                    params=a.get("params", {}),
                ))
        except json.JSONDecodeError:
            pass
        # Remove the code fence from the reply text
        reply_text = content[:action_match.start()] + content[action_match.end():]
        reply_text = reply_text.strip()
    return actions, reply_text


@router.post("")
@router.post("/")
@limit_30_per_minute  # 30 chat messages per minute per IP when slowapi is available
async def chat_endpoint(
    request: Request,  # Required by slowapi
    data: ChatRequest,
    user_id: UUID = Depends(get_current_user),
) -> dict[str, Any]:
    if not data.message or not data.message.strip():
        raise HTTPException(status_code=400, detail="Empty input")

    # ── Detect plan mention (offload DB to thread) ──────────────────────────────
    mentioned_plan_id, mentioned_plan_title = await _detect_plan_mention(data.message, user_id)
    system_prompt = None
    plan_actions: list[PlanChatAction] = []
    context_block = None

    if mentioned_plan_id:
        # Plan detected — build plan-specific context
        context_block = await _build_plan_context_block(mentioned_plan_id, user_id)
        if context_block:
            system_prompt = f"{PLAN_ACTIONS_SYSTEM_PROMPT}\n\n=== CURRENT PLAN CONTEXT ===\n{context_block}"
            logger.debug("plan_mentioned=%s", mentioned_plan_title)
        else:
            mentioned_plan_id = None
            mentioned_plan_title = None

    if not system_prompt:
        # No plan mentioned — minimal general chat prompt
        system_prompt = (
            "You are Life Agent — a friendly, helpful AI assistant and life coach. "
            "Be warm, direct, and concise. Give practical advice. "
            "If the user asks about their plans or schedule, tell them you can help with that — "
            "just mention a plan by name and you'll have full context."
        )

    try:
        # Use guided handler for guided panel inputs
        if data.source == "guided":
            route_type = _route_query(data.message)
            guided_prompt = GUIDED_SYSTEM_PROMPT
            if mentioned_plan_id and context_block:
                guided_prompt = f"{PLAN_ACTIONS_SYSTEM_PROMPT}\n\n=== CURRENT PLAN CONTEXT ===\n{context_block}\n\n{GUIDED_SYSTEM_PROMPT}"
            reply = await asend_chat_guided(user_id, data.message, route_type, guided_prompt)
            return {"reply": reply, "route_type": route_type}

        # Regular chat handler — build messages from history if provided
        chat_messages = data.history if data.history else []
        chat_messages.append({"role": "user", "content": data.message})

        # ── Run main chat + intent classification IN PARALLEL ────────────────
        raw_reply_coro = asend_chat(user_id, chat_messages, system=system_prompt)
        intent_coro = _classify_intent(data.message, user_id)
        raw_reply, intent_data = await asyncio.gather(raw_reply_coro, intent_coro)

        # Parse plan-actions if a plan was mentioned
        reply = raw_reply
        if mentioned_plan_id:
            plan_actions, reply = _parse_plan_actions(raw_reply)

        # ── Handle adjustment from classified intent ─────────────────────────
        adjustment_note = await _handle_adjustment(user_id, intent_data)

        if adjustment_note:
            reply = f"{reply}\n\n_{adjustment_note}_"

        return {"reply": reply, "actions": [a.model_dump() for a in plan_actions], "mentioned_plan": mentioned_plan_title}
    except LLMProviderError as e:
        detail = str(e)
        logger.error("mistral_error=%s", detail)
        raise HTTPException(status_code=500, detail=detail)
    except Exception as e:
        detail = f"Chat failed: {str(e)}"
        logger.error("chat_error=%s", detail)
        raise HTTPException(status_code=500, detail=detail)
