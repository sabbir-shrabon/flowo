# Task List

## To Do
- [x] Investigate why default API calling fails for new users without a BYOK API key.
- [x] Understand how API keys are resolved in the backend (`llm_client.py` or similar).
- [x] Fix the API key resolution logic so the default key is used when the user hasn't provided one.
- [x] Test the chat call for a user without a BYOK API key.

## Done
- [x] Initialized `todo.md` to track context and work progress.
- [x] Investigated why default API calling fails for new users without a BYOK API key.
- [x] Tested the chat call for new and existing users without a BYOK API key (It succeeds in code).
- [x] Found the issue: Error swallowing in `llm_client.py` and `chat.py`. 
- [x] Fixed `send_chat` in `llm_client.py` to properly raise the original exception when `_call_managed()` returns `None` (preventing silent `None` returns on 429/401 errors which caused type errors downstream).
- [x] Updated `backend/routers/chat.py` to return the specific `LLMProviderError` message to the frontend instead of a generic 500 error, giving the user proper feedback on what failed (e.g., missing env variables or rate limits).
