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
- [x] Investigated BYOK persistence across login/logout sessions. Verified that both the API key and the "Own API Key (BYOK)" toggle state (`use_managed_key`) are saved in the Supabase `users` table and successfully restored on login.
- [x] Investigated how the system calculates the current working day for a plan. Verified that `backend/adaptive/services/scheduler.py` uses `_current_working_day()` to count how many configured `working_days` (default Mon-Fri) have elapsed since the plan's `start_date` (stored in `schedule_prefs` or falling back to `created_at`), iterating day-by-day up to the current date.
- [x] Investigated where the adopted date is stored in the database. Verified that it is **not** a standalone column. It is stored inside the `schedule_prefs` column (which is a `jsonb` data type) in the `plans` table, typically as `{"start_date": "YYYY-MM-DD"}`. If it's missing from this JSON object, the system falls back to the `created_at` timestamp column.
