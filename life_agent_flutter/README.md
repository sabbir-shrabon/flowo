# life_agent_flutter

Life Agent Flutter app (Supabase auth + FastAPI backend).

## Getting Started

### Configuration (required)

This app uses build-time environment variables via `--dart-define`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `API_BASE_URL` (optional; if omitted, defaults to localhost / Android emulator defaults)

Example:

```bash
flutter run ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

If you prefer, copy `.env.example` as a reference for the keys you need (the app does not read `.env` automatically).
