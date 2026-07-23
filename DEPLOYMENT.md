# Deployment Guide

This repo is set up for:

- FastAPI backend on Render
- Flutter web frontend on Vercel or Netlify

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
- `FRONTEND_URL`
- `LLM_PROVIDER`
- Provider-specific keys you actually use, such as `OPENAI_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, or `GROQ_API_KEY`

Recommended `FRONTEND_URL` value:

```text
https://YOUR_SITE.netlify.app
```

Notes:

- The backend package lives in `backend/`, so the start command must be `uvicorn backend.main:app`.
- Render free tier sleeps after inactivity.
- `CORS_ORIGINS` is still supported for comma-separated extra origins, but `FRONTEND_URL` is the easiest setting for the deployed Netlify URL. The default `CORS_ORIGIN_REGEX` also allows Netlify preview and production domains.

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

## 3. Frontend on Vercel or Netlify

Recommended settings for the prebuilt-output workflow:

- Build the Flutter app locally first with the required `--dart-define` values
- Deploy the generated `life_agent_flutter/build/web` folder as static hosting output
- SPA fallback is already included via `life_agent_flutter/web/_redirects` and root `netlify.toml`

For Vercel:

- Import the same GitHub repository into Vercel
- Framework preset: `Other`
- Root directory: `life_agent_flutter/build/web`
- Build command: leave blank
- Output directory: `.`

For Netlify:

- Publish directory: `life_agent_flutter/build/web`
- If you connect the whole repo, use the included [netlify.toml](/d:/my%20projects/my%20research/life%20agent/netlify.toml)
- Add these Netlify environment variables before deploying:
  `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL`, `GOOGLE_WEB_CLIENT_ID`
- Set `API_BASE_URL` to your Render backend URL, for example:
  `https://YOUR-RENDER-SERVICE.onrender.com`
- If you drag-and-drop deploy manually, upload the contents of `life_agent_flutter/build/web`

If Netlify builds from Git, it must receive those values as environment variables because Flutter web reads them at build time through `--dart-define`. A plain `flutter build web --release` on Netlify will produce the same "Missing web build configuration" error you saw locally.

Each frontend update flow:

1. Rebuild Flutter web locally with the correct `--dart-define` values
2. Commit the updated `life_agent_flutter/build/web` files
3. Push to GitHub
4. Vercel or Netlify redeploys automatically

## 4. OAuth updates for production

You must also update external dashboards manually:

- Google Cloud OAuth: add your Vercel or Netlify domain under authorized JavaScript origins
- Supabase Auth URL configuration: add your Vercel or Netlify domain as Site URL or Additional Redirect URL

Without that, Google sign-in will fail on the live site even if local development works.
