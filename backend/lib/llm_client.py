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

from cachetools import TTLCache

# Cache decrypted keys for 10 minutes to avoid DB hits, max 1000 users.
_USER_CLIENT_CACHE = TTLCache(maxsize=1000, ttl=600)

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
    db_api_key = None
    db_provider = None
    db_model = None
    db_use_managed_key = True
    db_fallback_to_managed = True
    db_base_url = None
    db_agent_id = None
    db_organization_id = None

    if supabase:
        try:
            _, data = supabase.table("users").select("llm_provider, llm_model, llm_api_key, use_managed_key, fallback_to_managed, llm_base_url, llm_agent_id, llm_organization_id").eq("id", uid_str).execute()
            if data:
                row = data[0]
                db_provider = row.get("llm_provider")
                db_model = row.get("llm_model")
                db_use_managed_key = row.get("use_managed_key") if row.get("use_managed_key") is not None else True
                db_fallback_to_managed = row.get("fallback_to_managed") if row.get("fallback_to_managed") is not None else True
                db_base_url = row.get("llm_base_url")
                db_agent_id = row.get("llm_agent_id")
                db_organization_id = row.get("llm_organization_id")
                encrypted_key = row.get("llm_api_key")
                if encrypted_key:
                    db_api_key = decrypt_key(encrypted_key)
                    if db_api_key is None:
                        # decrypt_key returns None when ENCRYPTION_MASTER_KEY is missing or wrong
                        logger.error(
                            "get_client_for_user: failed to decrypt DB key for user=%s. "
                            "Check that ENCRYPTION_MASTER_KEY is set correctly on the server.",
                            uid_str,
                        )
                else:
                    logger.debug("get_client_for_user: no llm_api_key stored in DB for user=%s", uid_str)
            else:
                logger.debug("get_client_for_user: no users row found for user=%s", uid_str)
        except Exception as exc:
            logger.error("get_client_for_user: DB lookup failed for user=%s: %s", uid_str, exc)
    else:
        logger.warning("get_client_for_user: Supabase client not available; falling back to env vars")

    # Resolve provider (DB value beats env default)
    provider = (db_provider or settings.llm_provider or "mistral").lower()
    
    # Determine if user is in BYOK mode (has their own key in DB)
    is_byok = db_api_key is not None

    if provider == "openai":
        model = db_model or settings.openai_model
        api_key = db_api_key or settings.openai_api_key
        # Only inherit env extras when NOT in BYOK mode
        base_url = db_base_url or (settings.openai_base_url if not is_byok else None)
        organization_id = db_organization_id or (settings.openai_organization_id if not is_byok else None)
        agent_id = db_agent_id
    elif provider == "gemini":
        model = db_model or settings.gemini_model
        api_key = db_api_key or settings.gemini_api_key
        base_url = db_base_url
        agent_id = db_agent_id
        organization_id = db_organization_id
    elif provider == "ollama":
        model = db_model or settings.ollama_model
        base_url = db_base_url or settings.ollama_base_url
        api_key = db_api_key
        agent_id = db_agent_id
        organization_id = db_organization_id
    elif provider == "groq":
        model = db_model or settings.groq_model
        api_key = db_api_key or settings.groq_api_key
        base_url = db_base_url
        agent_id = db_agent_id
        organization_id = db_organization_id
    elif provider == "mistral":
        model = db_model or settings.mistral_model
        api_key = db_api_key or settings.mistral_api_key
        # Only use env agent_id/base_url when NOT in BYOK mode
        agent_id = db_agent_id or (settings.mistral_agent_id if not is_byok else None)
        base_url = db_base_url or (settings.mistral_base_url if not is_byok else None)
        organization_id = db_organization_id
    else:
        logger.warning("get_client_for_user: unknown provider '%s', defaulting to mistral", provider)
        provider = "mistral"
        model = db_model or settings.mistral_model
        api_key = db_api_key or settings.mistral_api_key
        agent_id = db_agent_id or (settings.mistral_agent_id if not is_byok else None)
        base_url = db_base_url or (settings.mistral_base_url if not is_byok else None)
        organization_id = db_organization_id

    logger.debug(
        "get_client_for_user: user=%s provider=%s model=%s key_source=%s",
        uid_str, provider, model,
        "db" if db_api_key else ("env" if api_key else "NONE"),
    )

    client_config = {
        "provider": provider,
        "model": model,
        "api_key": api_key,
        "base_url": base_url,
        "agent_id": agent_id,
        "organization_id": organization_id,
        "use_managed_key": db_use_managed_key,
        "fallback_to_managed": db_fallback_to_managed,
    }

    # Only cache when we have a valid key — if the key is missing we want to
    # retry on the next request (e.g. after the user saves their key).
    if api_key or db_use_managed_key:
        _USER_CLIENT_CACHE[uid_str] = client_config
    else:
        logger.warning(
            "get_client_for_user: no API key resolved for user=%s provider=%s — not caching",
            uid_str, provider,
        )

    return client_config

def validate_provider_config(provider: str, model: str, api_key: str, base_url: str | None = None, agent_id: str | None = None) -> bool:
    """Make a lightweight request to validate the key and config."""
    if not api_key and provider != "ollama":
        return False
        
    try:
        if provider == "openai":
            url = f"{base_url.rstrip('/') if base_url else 'https://api.openai.com/v1'}/models"
            resp = requests.get(url, headers={"Authorization": f"Bearer {api_key}"}, timeout=10)
            return resp.status_code == 200
        elif provider == "mistral":
            if agent_id:
                # If agent_id is provided, we might not need to validate models, but let's just validate the key via models endpoint
                url = f"{base_url.rstrip('/') if base_url else 'https://api.mistral.ai/v1'}/models"
            else:
                url = f"{base_url.rstrip('/') if base_url else 'https://api.mistral.ai/v1'}/models"
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
    base_url = client.get("base_url")
    agent_id = client.get("agent_id")
    organization_id = client.get("organization_id")
    use_managed_key = client.get("use_managed_key", True)
    fallback_to_managed = client.get("fallback_to_managed", True)

    final_messages = list(messages)
    if system:
        has_system = any(m.get("role") == "system" for m in final_messages)
        if not has_system:
            final_messages.insert(0, {"role": "system", "content": system})

    def _call_managed():
        if settings.managed_llm_api_key:
            import litellm
            try:
                resp = litellm.completion(
                    model=settings.managed_llm_model,
                    messages=final_messages,
                    api_key=settings.managed_llm_api_key
                )
                return resp.choices[0].message.content
            except Exception as e:
                raise LLMProviderError(f"Managed LLM call failed: {str(e)}")
        return None

    if use_managed_key:
        managed_resp = _call_managed()
        if managed_resp is not None:
            return managed_resp
        # If managed_llm_api_key is not set, fall through to use the specific provider's env key

    if not api_key and provider != "ollama":
        if fallback_to_managed:
            logger.warning(f"No API key for {provider}, falling back to managed key.")
            managed_resp = _call_managed()
            if managed_resp is not None:
                return managed_resp
        raise LLMProviderError(
            f"No API key found for provider '{provider}'. "
            "Please go to Settings → LLM and save your API key or configure it on the server."
        )

    try:
        if provider == "openai" or provider == "groq":
            default_url = "https://api.openai.com/v1/chat/completions" if provider == "openai" else "https://api.groq.com/openai/v1/chat/completions"
            url = f"{base_url.rstrip('/')}/chat/completions" if base_url else default_url
            payload = {"model": model, "messages": final_messages}
            headers = _get_headers(api_key)
            if organization_id:
                headers["OpenAI-Organization"] = organization_id
            resp = requests.post(url, json=payload, headers=headers, timeout=30)
            if resp.status_code in [401, 403, 429]:
                raise requests.exceptions.HTTPError(response=resp)
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"]

        elif provider == "mistral":
            try:
                from mistralai.client import Mistral
                m_client = Mistral(api_key=api_key, server_url=base_url if base_url else "https://api.mistral.ai")
                if agent_id:
                    try:
                        resp = m_client.agents.complete(agent_id=agent_id, messages=final_messages)
                        return resp.choices[0].message.content
                    except Exception as agent_err:
                        if "Agent not found" in str(agent_err) or "invalid_agent" in str(agent_err):
                            logger.warning("Agent '%s' not found, falling back to chat.complete with model=%s", agent_id, model)
                        else:
                            raise
                # Regular chat completion (or fallback from failed agent)
                resp = m_client.chat.complete(model=model, messages=final_messages)
                return resp.choices[0].message.content
            except ImportError:
                raise LLMProviderError("Mistral SDK not installed.")
            except Exception as e:
                if fallback_to_managed and ("401" in str(e) or "429" in str(e) or "403" in str(e)):
                    logger.warning(f"Mistral BYOK failed, falling back to managed key. Error: {e}")
                    return _call_managed()
                raise LLMProviderError(f"Mistral call failed: {str(e)}")

        elif provider == "gemini":
            prompt = ""
            for m in final_messages:
                prompt += f"{m['role']}: {m['content']}\n"
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            payload = {"contents": [{"parts": [{"text": prompt}]}]}
            resp = requests.post(url, json=payload, headers=_get_headers(), timeout=30)
            if resp.status_code in [401, 403, 429]:
                raise requests.exceptions.HTTPError(response=resp)
            resp.raise_for_status()
            return resp.json()["candidates"][0]["content"]["parts"][0]["text"]

        elif provider == "ollama":
            url = f"{base_url.rstrip('/') if base_url else 'http://localhost:11434'}/api/chat"
            payload = {"model": model, "messages": final_messages, "stream": False}
            resp = requests.post(url, json=payload, headers=_get_headers(), timeout=30)
            resp.raise_for_status()
            return resp.json()["message"]["content"]

        raise LLMProviderError(f"Unknown provider: {provider}")

    except requests.exceptions.HTTPError as e:
        if fallback_to_managed and e.response is not None and e.response.status_code in [401, 403, 429]:
            logger.warning(f"BYOK failed with {e.response.status_code}, falling back to managed key.")
            return _call_managed()
        raise LLMProviderError(f"{provider.capitalize()} call failed: {str(e)}")
    except Exception as e:
        raise LLMProviderError(f"{provider.capitalize()} call failed: {str(e)}")

async def asend_chat(user_id: UUID | str, messages: list[dict[str, Any]], system: str | None = None) -> str:
    return await asyncio.to_thread(send_chat, user_id, messages, system)

async def asend_chat_guided(user_id: UUID | str, user_message: str, route_type: str, system_prompt: str) -> str:
    messages = [{"role": "user", "content": user_message}]
    
    # We no longer apply Mistral-specific formatting to all responses
    raw_reply = await asend_chat(user_id, messages, system=system_prompt)
    
    return raw_reply
