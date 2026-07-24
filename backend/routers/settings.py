from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Any
from uuid import UUID

from backend.auth import get_current_user
from backend.lib.db import get_supabase_client
from backend.lib.crypto import encrypt_key, mask_key
from backend.lib.llm_client import validate_api_key, clear_user_cache

router = APIRouter(prefix="/api/settings", tags=["settings"])

class LLMSettingsUpdate(BaseModel):
    provider: str
    model: str
    api_key: str | None = None

@router.get("/llm")
def get_llm_settings(user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    supabase = get_supabase_client()
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")
    
    _, data = supabase.table("users").select("llm_provider, llm_model, llm_api_key").eq("id", str(user_id)).execute()
    if not data:
        return {"provider": "mistral", "model": "mistral-small-latest", "api_key": None}
    
    user_row = data[0]
    provider = user_row.get("llm_provider") or "mistral"
    model = user_row.get("llm_model") or "mistral-small-latest"
    raw_key = user_row.get("llm_api_key")
    
    # We never return the decrypted key. We return a masked string if they have one.
    return {
        "provider": provider,
        "model": model,
        "api_key": mask_key(raw_key) if raw_key else None
    }

@router.post("/llm")
def update_llm_settings(data: LLMSettingsUpdate, user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    supabase = get_supabase_client()
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")

    encrypted_key = None
    if data.api_key and data.api_key != "****" and not data.api_key.startswith("sk-..."):
        # They provided a new key, let's validate it
        if not validate_api_key(data.provider, data.model, data.api_key):
            raise HTTPException(status_code=400, detail="Invalid API key for the selected provider.")
        encrypted_key = encrypt_key(data.api_key)
        if not encrypted_key:
            raise HTTPException(status_code=500, detail="Encryption failed. Check server configuration.")

    update_payload = {
        "llm_provider": data.provider,
        "llm_model": data.model
    }
    
    if encrypted_key:
        update_payload["llm_api_key"] = encrypted_key

    # Update in DB
    supabase.table("users").update(update_payload).eq("id", str(user_id)).execute()

    # Clear cache
    clear_user_cache(user_id)

    return {"success": True, "message": "Settings updated"}

@router.delete("/llm")
def clear_llm_key(user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    supabase = get_supabase_client()
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")
        
    supabase.table("users").update({"llm_api_key": None}).eq("id", str(user_id)).execute()
    clear_user_cache(user_id)
    return {"success": True, "message": "API key cleared"}
