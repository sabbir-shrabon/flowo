# Deployment Guide

This repo is set up for:

- FastAPI backend on Render
- Flutter web frontend on Vercel

## 1. Backend on Render

This repo now includes:

- Root [requirements.txt](/d:/my%20projects/my%20research/life%20agent/requirements.txt)
- Root [render.yaml](/d:/my%20projects/my%20research/life%20agent/render.yaml)

Render should run from the repository root with:

- Build command: `pip install -r requirements.txt`
- Start command: `uvicorn backend.main:app --host 0.0.0.0 --port $PORT`
- Health check path: `/api/health`

Environment variables you will need to add in Render:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_JWT_SECRET`
- `SUPABASE_ANON_KEY`
- `LLM_PROVIDER`
- Provider-specific keys you actually use, such as `OPENAI_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, or `GROQ_API_KEY`

Notes:

- The backend package lives in `backend/`, so the start command must be `uvicorn backend.main:app`.
- Render free tier sleeps after inactivity.

## 2. Flutter web production build

The Flutter app already supports a production backend URL through `API_BASE_URL`. You do not need to hardcode your Render URL in Dart source.

Build from [life_agent_flutter](/d:/my%20projects/my%20research/life%20agent/life_agent_flutter):

```bash
flutter build web --release ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com ^
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Or run the helper script:

```powershell
.\build_web.ps1 -ApiBaseUrl https://YOUR-RENDER-SERVICE.onrender.com
```

The output is:

- [life_agent_flutter/build/web](/d:/my%20projects/my%20research/life%20agent/life_agent_flutter/build/web)

This path is now allowed through `.gitignore` so you can commit it if you want Vercel to deploy the prebuilt output directly.

## 3. Frontend on Vercel

Recommended settings for the prebuilt-output workflow:

- Import the same GitHub repository into Vercel
- Framework preset: `Other`
- Root directory: `life_agent_flutter/build/web`
- Build command: leave blank
- Output directory: `.`

Each frontend update flow:

1. Rebuild Flutter web locally with the correct `--dart-define` values
2. Commit the updated `life_agent_flutter/build/web` files
3. Push to GitHub
4. Vercel redeploys automatically

## 4. OAuth updates for production

You must also update external dashboards manually:

- Google Cloud OAuth: add your Vercel domain under authorized JavaScript origins
- Supabase Auth URL configuration: add your Vercel domain as Site URL or Additional Redirect URL

Without that, Google sign-in will fail on the live site even if local development works.
