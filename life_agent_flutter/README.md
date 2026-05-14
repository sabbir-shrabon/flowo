# life_agent_flutter

Life Agent Flutter app (Supabase auth + FastAPI backend).

## Getting Started

### Configuration (required)

This app uses build-time environment variables via `--dart-define`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `API_BASE_URL` (optional; if omitted, defaults to localhost / Android emulator defaults)
- `GOOGLE_WEB_CLIENT_ID` (required for Flutter web Google Sign-In; also keep it in `.env` if you use the shared run scripts)
- `GOOGLE_IOS_CLIENT_ID` (currently unused by the app)

Example:

```bash
flutter run ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 ^
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Production web build example:

```bash
flutter build web --release ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com ^
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Or use the helper script from `life_agent_flutter/` after updating `.env`:

```powershell
.\build_web.ps1 -ApiBaseUrl https://YOUR-RENDER-SERVICE.onrender.com
```

If you prefer, copy `.env.example` as a reference for the keys you need (the app does not read `.env` automatically).

For Flutter web Google sign-in, also configure these outside the repo:

- Google Cloud OAuth authorized JavaScript origin: `http://localhost:5000`
- Supabase Auth site URL or additional redirect URL: `http://localhost:5000`

For production web deployment, also add:

- Your Vercel site URL as a Google Cloud OAuth authorized JavaScript origin, for example `https://yourappname.vercel.app`
- Your Vercel site URL in Supabase Auth -> URL Configuration -> Site URL or Additional Redirect URLs

For Flutter mobile Google sign-in, the app now uses Supabase OAuth with a deep link callback:

- Mobile redirect URL: `com.lifeagent.life_agent_flutter://login-callback/`
- Add that exact URL to Supabase Auth -> URL Configuration -> Additional Redirect URLs
- Keep Google enabled in Supabase Auth Providers
- On Android and iOS, the app is already configured to receive the `com.lifeagent.life_agent_flutter` scheme
