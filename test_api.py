"""
test_api.py — Quick smoke-test to verify the LLM provider is responding.

Usage (from project root, with venv activated):
    python test_api.py
"""

import sys
import os

# Ensure the project root is on the Python path so `backend.*` imports work.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from backend.config import settings
from backend.lib.llm_client import send_chat, LLMProviderError

# Use a fixed "dev" user ID so we fall back to env-var config
# (no DB lookup needed for a quick test).
DEV_USER_ID = "00000000-0000-0000-0000-000000000000"

TEST_MESSAGE = "Say hello in one sentence."


def main():
    print("=" * 60)
    print("  Life Agent — LLM Smoke Test")
    print("=" * 60)
    print()
    print(f"  Provider : {settings.llm_provider}")

    if settings.llm_provider == "openai":
        model = settings.openai_model
        has_key = bool(settings.openai_api_key)
    elif settings.llm_provider == "gemini":
        model = settings.gemini_model
        has_key = bool(settings.gemini_api_key)
    elif settings.llm_provider == "groq":
        model = settings.groq_model
        has_key = bool(settings.groq_api_key)
    elif settings.llm_provider == "mistral":
        model = settings.mistral_model
        has_key = bool(settings.mistral_api_key)
    elif settings.llm_provider == "ollama":
        model = settings.ollama_model
        has_key = True  # ollama doesn't need a key
    else:
        model = "unknown"
        has_key = False

    print(f"  Model    : {model}")
    print(f"  API Key  : {'[OK] set' if has_key else '[!!] MISSING'}")
    print()

    if not has_key:
        print("  [FAIL] No API key configured. Check backend/.env")
        sys.exit(1)

    print(f'  Sending -> "{TEST_MESSAGE}"')
    print()

    try:
        reply = send_chat(
            DEV_USER_ID,
            [{"role": "user", "content": TEST_MESSAGE}],
        )
        print(f"  [OK] SUCCESS - LLM replied:")
        print()
        # Encode to ASCII with replacement so emojis/special chars don't crash Windows console
        safe_reply = reply.encode("ascii", errors="replace").decode("ascii")
        print(f"    {safe_reply}")
        print()
        print("=" * 60)
    except LLMProviderError as e:
        print(f"  [FAIL] LLM provider error:")
        print(f"    {e}")
        print()
        print("=" * 60)
        sys.exit(1)
    except Exception as e:
        print(f"  [FAIL] Unexpected error:")
        print(f"    {type(e).__name__}: {e}")
        print()
        print("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
