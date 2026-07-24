import logging
import asyncio
from typing import Any
from uuid import UUID
import requests

from backend.config import settings
from backend.lib.db import get_supabase_client
from backend.lib.crypto import decrypt_key

logger = logging.getLogger(__name__)

class LLMProviderError(Exception):
    pass

# Simple cache for decrypted keys to avoid DB hit on every message.
# In a real production app with many users, we'd use Redis or expiring TTL cache.
_USER_CLIENT_CACHE = {}

def clear_user_cache(user_id: UUID):
    """Clear the cached settings for a user when they update them."""
    if str(user_id) in _USER_CLIENT_CACHE:
        del _USER_CLIENT_CACHE[str(user_id)]

def get_client_for_user(user_id: UUID | str) -> dict:
    """
    Fetch the user's preferred LLM configuration from DB.
    Fallback to env vars if not set.
    Returns: {"provider": str, "model": str, "api_key": str}
    """
    uid_str = str(user_id)
    if uid_str in _USER_CLIENT_CACHE:
        return _USER_CLIENT_CACHE[uid_str]

    supabase = get_supabase_client()
    db_provider = None
    db_model = None
    db_api_key = None

    if supabase:
        _, data = supabase.table("users").select("llm_provider, llm_model, llm_api_key").eq("id", uid_str).execute()
        if data:
            row = data[0]
            db_provider = row.get("llm_provider")
            db_model = row.get("llm_model")
            encrypted_key = row.get("llm_api_key")
            if encrypted_key:
                db_api_key = decrypt_key(encrypted_key)

    # Fallbacks
    provider = db_provider or settings.llm_provider
    
    if provider.lower() == "openai":
        model = db_model or settings.openai_model
        api_key = db_api_key or settings.openai_api_key
    elif provider.lower() == "gemini":
        model = db_model or settings.gemini_model
        api_key = db_api_key or settings.gemini_api_key
    elif provider.lower() == "ollama":
        model = db_model or settings.ollama_model
        api_key = db_api_key or settings.ollama_base_url
    elif provider.lower() == "groq":
        model = db_model or settings.groq_model
        api_key = db_api_key or settings.groq_api_key
    else:
        provider = "mistral"
        model = db_model or settings.mistral_model
        api_key = db_api_key or settings.mistral_api_key

    client_config = {
        "provider": provider.lower(),
        "model": model,
        "api_key": api_key
    }
    
    _USER_CLIENT_CACHE[uid_str] = client_config
    return client_config

def validate_api_key(provider: str, model: str, api_key: str) -> bool:
    """Make a lightweight request to validate the key."""
    if not api_key:
        return False
        
    try:
        if provider == "openai":
            url = "https://api.openai.com/v1/models"
            resp = requests.get(url, headers={"Authorization": f"Bearer {api_key}"}, timeout=10)
            return resp.status_code == 200
        elif provider == "mistral":
            url = "https://api.mistral.ai/v1/models"
            resp = requests.get(url, headers={"Authorization": f"Bearer {api_key}"}, timeout=10)
            return resp.status_code == 200
        elif provider == "gemini":
            url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
            resp = requests.get(url, timeout=10)
            return resp.status_code == 200
        elif provider == "groq":
            url = "https://api.groq.com/openai/v1/models"
            resp = requests.get(url, headers={"Authorization": f"Bearer {api_key}"}, timeout=10)
            return resp.status_code == 200
    except Exception as e:
        logger.error(f"Validation failed for {provider}: {e}")
        return False
        
    # If we don't know the provider, assume valid (e.g. ollama)
    return True

# ── Unified Sending Methods ───────────────────────────────────────────────────

def _get_headers(auth_token: str = None) -> dict:
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "LifeAgent/1.0"
    }
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    return headers

def send_chat(user_id: UUID | str, messages: list[dict[str, Any]], system: str | None = None) -> str:
    client = get_client_for_user(user_id)
    provider = client["provider"]
    model = client["model"]
    api_key = client["api_key"]

    if not api_key and provider != "ollama":
        raise LLMProviderError(f"API key missing for provider {provider}. Please update your settings.")

    final_messages = list(messages)
    if system:
        has_system = any(m.get("role") == "system" for m in final_messages)
        if not has_system:
            final_messages.insert(0, {"role": "system", "content": system})

    if provider == "openai" or provider == "groq":
        url = "https://api.openai.com/v1/chat/completions" if provider == "openai" else "https://api.groq.com/openai/v1/chat/completions"
        payload = {"model": model, "messages": final_messages}
        try:
            resp = requests.post(url, json=payload, headers=_get_headers(api_key), timeout=30)
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"]
        except Exception as e:
            raise LLMProviderError(f"{provider.capitalize()} call failed: {str(e)}")

    elif provider == "mistral":
        try:
            from mistralai.client import Mistral
            m_client = Mistral(api_key=api_key)
            resp = m_client.chat.complete(model=model, messages=final_messages)
            return resp.choices[0].message.content
        except ImportError:
            raise LLMProviderError("Mistral SDK not installed.")
        except Exception as e:
            raise LLMProviderError(f"Mistral call failed: {str(e)}")

    elif provider == "gemini":
        prompt = ""
        for m in final_messages:
            prompt += f"{m['role']}: {m['content']}\n"
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
        payload = {"contents": [{"parts": [{"text": prompt}]}]}
        try:
            resp = requests.post(url, json=payload, headers=_get_headers(), timeout=30)
            resp.raise_for_status()
            return resp.json()["candidates"][0]["content"]["parts"][0]["text"]
        except Exception as e:
            raise LLMProviderError(f"Gemini call failed: {str(e)}")

    elif provider == "ollama":
        url = f"{api_key.rstrip('/')}/api/chat" if api_key else "http://localhost:11434/api/chat"
        payload = {"model": model, "messages": final_messages, "stream": False}
        try:
            resp = requests.post(url, json=payload, headers=_get_headers(), timeout=30)
            resp.raise_for_status()
            return resp.json()["message"]["content"]
        except Exception as e:
            raise LLMProviderError(f"Ollama call failed: {str(e)}")

    raise LLMProviderError(f"Unknown provider: {provider}")

async def asend_chat(user_id: UUID | str, messages: list[dict[str, Any]], system: str | None = None) -> str:
    return await asyncio.to_thread(send_chat, user_id, messages, system)

async def asend_chat_guided(user_id: UUID | str, user_message: str, route_type: str, system_prompt: str) -> str:
    messages = [{"role": "user", "content": user_message}]
    
    # Mistral provider had a specific formatter, we apply it here universally
    raw_reply = await asend_chat(user_id, messages, system=system_prompt)
    
    from backend.lib.mistral_provider import _format_guided_response
    return _format_guided_response(raw_reply, route_type)
