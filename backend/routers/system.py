from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Any

from backend.lib.llm import chatResponse, LLMProviderError
from backend.lib.db import get_supabase_client
from backend.config import settings

router = APIRouter(prefix="/api", tags=["system"])

class TestPrompt(BaseModel):
    prompt: str

@router.get("/health")
def health_check() -> dict[str, Any]:
    return {"ok": True}

@router.post("/test-llm")
def test_llm(data: TestPrompt) -> dict[str, Any]:
    try:
        response = chatResponse(data.prompt)
        
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
