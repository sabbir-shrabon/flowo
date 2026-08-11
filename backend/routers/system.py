from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Any
from uuid import UUID

from backend.lib.llm_client import send_chat, LLMProviderError
from backend.lib.db import get_supabase_client
from backend.auth import get_current_user
from backend.config import settings

router = APIRouter(prefix="/api", tags=["system"])

class TestPrompt(BaseModel):
    prompt: str

@router.get("/health")
def health_check():
    try:
        supabase = get_supabase_client()
        # Simple query to verify DB connectivity
        supabase.table("users").select("id").limit(1).execute()
        return {"ok": True, "db_connected": True}
    except Exception as e:
        return {"ok": False, "db_connected": False, "error": str(e)}

@router.post("/test-llm")
def test_llm(data: TestPrompt, user_id: UUID = Depends(get_current_user)) -> dict[str, Any]:
    try:
        messages = [{"role": "user", "content": data.prompt}]
        response = send_chat(str(user_id), messages)
        
        # Test Supabase insert if fully configured
        supabase = get_supabase_client()
        persisted = False
        if supabase:
            try:
                # Store diagnostic LLM requests separately from user conversations.
                supabase.table("llm_test_logs").insert({
                    "role": "system",
                    "content": f"Test prompt: {data.prompt} => {response}"
                }).execute()
                persisted = True
            except Exception as e:
                print(f"Supabase persistence error: {e}")
                pass
                
        return {
            "success": True,
            "response": response,
            "persisted": persisted
        }
    except LLMProviderError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
