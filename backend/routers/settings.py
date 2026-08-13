from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Any
from uuid import UUID

from backend.auth import get_current_user
from backend.lib.db import get_supabase_client
from backend.lib.crypto import encrypt_key, mask_key
from backend.lib.llm_client import validate_provider_config, clear_user_cache
from backend.lib.provider_registry import PROVIDER_REGISTRY

router = APIRouter(prefix="/api/settings", tags=["settings"])

class LLMSettingsUpdate(BaseModel):
    provider: str
    model: str
    api_key: str | None = None
    base_url: str | None = None
    agent_id: str | None = None
    organization_id: str | None = None
    use_managed_key: bool = True
    fallback_to_managed: bool = True

@router.get("/llm/providers")
def get_llm_providers() -> dict[str, Any]:
    return PROVIDER_REGISTRY

@router.get("/llm")
def get_llm_settings(user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    supabase = get_supabase_client()
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")
    
    _, data = supabase.table("users").select("llm_api_key").eq("id", str(user_id)).execute()
    raw_key = data[0].get("llm_api_key") if data else None
    
    from backend.lib.llm_client import get_client_for_user
    client = get_client_for_user(user_id)
    
    # We never return the decrypted key. We return a masked string if they have one.
    return {
        "provider": client["provider"],
        "model": client["model"],
        "api_key": mask_key(raw_key) if raw_key else None,
        "base_url": client.get("base_url"),
        "agent_id": client.get("agent_id"),
        "organization_id": client.get("organization_id"),
        "use_managed_key": client.get("use_managed_key", True),
        "fallback_to_managed": client.get("fallback_to_managed", True)
    }

@router.post("/llm")
def update_llm_settings(data: LLMSettingsUpdate, user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    supabase = get_supabase_client()
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")

    encrypted_key = None
    if data.api_key and data.api_key != "****" and not data.api_key.startswith("sk-..."):
        # They provided a new key, let's validate it
        if not validate_provider_config(data.provider, data.model, data.api_key, data.base_url, data.agent_id):
            raise HTTPException(status_code=400, detail="Invalid API key or config for the selected provider.")
        encrypted_key = encrypt_key(data.api_key)
        if not encrypted_key:
            raise HTTPException(
                status_code=500,
                detail=(
                    "Server misconfiguration: ENCRYPTION_MASTER_KEY is not set. "
                    "Generate a key with `python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\"` "
                    "and add it as an environment variable on your server."
                ),
            )

    update_payload = {
        "llm_provider": data.provider,
        "llm_model": data.model,
        "llm_base_url": data.base_url,
        "llm_agent_id": data.agent_id,
        "llm_organization_id": data.organization_id,
        "use_managed_key": data.use_managed_key,
        "fallback_to_managed": data.fallback_to_managed
    }
    
    if encrypted_key:
        update_payload["llm_api_key"] = encrypted_key

    # Update in DB
    supabase.table("users").update(update_payload).eq("id", str(user_id)).execute()

    # Clear cache
    clear_user_cache(user_id)

    return {"success": True, "message": "Settings updated"}

class LLMTestRequest(BaseModel):
    provider: str
    model: str
    api_key: str | None = None
    base_url: str | None = None
    agent_id: str | None = None
    use_managed_key: bool = True

@router.post("/llm/test")
def test_llm_connection(data: LLMTestRequest, user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    # If using managed key, just do a lightweight check that litellm is configured
    if data.use_managed_key:
        from backend.config import settings
        if settings.managed_llm_api_key:
            return {"success": True, "message": "Managed key configuration is valid"}
        
        # Fall back to provider specific env keys
        provider = (data.provider or settings.llm_provider or "mistral").lower()
        env_key = getattr(settings, f"{provider}_api_key", None)
        if not env_key:
            raise HTTPException(status_code=500, detail=f"Managed key for {provider} is not configured on the server.")
        return {"success": True, "message": f"Server {provider} key configuration is valid"}
    
    # If not using managed key, validate the provided key
    if not data.api_key or data.api_key == "****" or data.api_key.startswith("sk-..."):
        # If they haven't provided a new key (it's masked), try to fetch the existing decrypted key from DB
        supabase = get_supabase_client()
        if not supabase:
            raise HTTPException(status_code=500, detail="Database not configured")
        _, user_data = supabase.table("users").select("llm_api_key").eq("id", str(user_id)).execute()
        if not user_data or not user_data[0].get("llm_api_key"):
            raise HTTPException(status_code=400, detail="No API key provided and none saved.")
        
        from backend.lib.crypto import decrypt_key
        actual_key = decrypt_key(user_data[0].get("llm_api_key"))
        if not actual_key:
            raise HTTPException(status_code=500, detail="Failed to decrypt saved API key.")
        
        if not validate_provider_config(data.provider, data.model, actual_key, data.base_url, data.agent_id):
            raise HTTPException(status_code=400, detail="Saved API key is invalid for this provider.")
    else:
        # Validate the new key they just typed in
        if not validate_provider_config(data.provider, data.model, data.api_key, data.base_url, data.agent_id):
            raise HTTPException(status_code=400, detail="Provided API key or config is invalid.")
            
    return {"success": True, "message": "Connection successful"}

@router.delete("/llm")
def clear_llm_key(user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    supabase = get_supabase_client()
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")
        
    supabase.table("users").update({"llm_api_key": None}).eq("id", str(user_id)).execute()
    clear_user_cache(user_id)
    return {"success": True, "message": "API key cleared"}
