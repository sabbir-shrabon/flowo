"""Memory Extractor — calls LLM to extract structured memory from conversation, saves as a single memory row."""

from __future__ import annotations

import asyncio
import json
from uuid import UUID

from backend.adaptive.db import AdaptiveStore
from backend.adaptive.models import MemoryKey, MemoryRow
from backend.lib.llm_client import send_chat


EXTRACTION_PROMPT = """You are a memory extraction engine. Analyze this conversation between a user and an AI planning assistant. Extract and return ONLY a JSON object with these fields:
{
"summary": "2-3 sentence summary of what the user wants to achieve",
"goal": "the core goal in one sentence",
"keywords": ["keyword1", "keyword2", ...],  // 5-10 specific keywords
"preferences": ["prefers mornings", "dislikes long sessions", ...],
"constraints": ["works late Wednesdays", "no weekends", ...],
"motivation": "why the user wants this goal",
"current_level": "beginner/intermediate/advanced or a description",
"domain": "fitness/language/skill/habit/other"
}
Return ONLY valid JSON. No explanation, no markdown."""

RETRY_PROMPT = """You previously failed to return valid JSON. You MUST return ONLY a raw JSON object — no markdown fences, no explanation, no extra text. Just the JSON. Try again:

{previous_response}

Return the corrected JSON now."""


def _call_llm(prompt: str, user_id: str) -> str:
    """Synchronous LLM call wrapper."""
    messages = [{"role": "user", "content": prompt}]
    return send_chat(user_id, messages)


def _clean_llm_response(raw: str) -> str:
    """Strip markdown fences and whitespace from LLM output."""
    content = raw.strip()
    if content.startswith("```json"):
        content = content[7:]
    elif content.startswith("```"):
        content = content[3:]
    if content.endswith("```"):
        content = content[:-3]
    return content.strip()


async def extract_and_save(
    user_id: str,
    conversation: list[dict],  # [{role: "user"|"assistant", content: str}]
    db: AdaptiveStore,
) -> MemoryRow:
    """
    1. Format conversation and send to LLM with extraction prompt
    2. Parse JSON response (retry once on parse failure with stricter prompt)
    3. Save full JSON as a single memory row via AdaptiveStore.create_memory()
    4. Return the MemoryRow
    """
    # Format conversation into a readable string for the LLM
    conv_text = "\n".join(
        f"{msg['role'].capitalize()}: {msg['content']}" for msg in conversation
    )

    full_prompt = f"{EXTRACTION_PROMPT}\n\nConversation:\n{conv_text}"

    # First LLM call
    raw = await asyncio.to_thread(_call_llm, full_prompt, str(user_id))
    cleaned = _clean_llm_response(raw)

    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        # Retry once with stricter prompt
        retry_prompt = RETRY_PROMPT.format(previous_response=cleaned)
        raw = await asyncio.to_thread(_call_llm, retry_prompt, str(user_id))
        cleaned = _clean_llm_response(raw)
        parsed = json.loads(cleaned)  # let this propagate if it still fails

    # Save the full JSON as a single memory row
    content = json.dumps(parsed)
    uid = UUID(user_id) if isinstance(user_id, str) else user_id

    memory_row = db.create_memory(
        user_id=uid,
        key=MemoryKey.context,
        value=content,
        source="chat_extraction",
    )

    return memory_row
