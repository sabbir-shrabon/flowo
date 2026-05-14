# Auth & Security Upgrade Summary

## Changes Made

### 1. Google OAuth Integration

**Files Modified:**
- `life_agent_flutter/lib/providers/auth_provider.dart` - Added `signInWithGoogle()` method
- `life_agent_flutter/lib/widgets/auth_modal.dart` - Added Google Sign-in button with logo

**How it works:**
1. User clicks "Sign in with Google" button
2. Supabase opens OAuth flow (popup on web, browser on mobile)
3. User authenticates with Google
4. Google returns auth code to Supabase
5. Supabase exchanges code for JWT tokens
6. App receives session and stores tokens securely

### 2. Security Enhancements

#### Backend Security Headers
**File:** `backend/main.py`

Added middleware that sets security headers on all responses:
- `X-Frame-Options: DENY` - Prevents clickjacking attacks
- `X-Content-Type-Options: nosniff` - Prevents MIME type sniffing
- `X-XSS-Protection: 1; mode=block` - XSS protection
- `Referrer-Policy: strict-origin-when-cross-origin` - Limits referrer leakage
- `Content-Security-Policy: default-src 'self'` - CSP

#### Rate Limiting
**Files:** `backend/main.py`, `backend/routers/chat.py`, `backend/adaptive/routes/router.py`

| Endpoint | Rate Limit | Reason |
|----------|-----------|--------|
| `/api/chat` | 30/minute | Expensive LLM calls |
| `/api/adaptive/plans/generate` | 10/minute | Plan generation is expensive |
| `/api/adaptive/plans/generate-from-answers` | 10/minute | Plan generation is expensive |
| `/api/adaptive/create-plan` | 10/minute | Plan generation is expensive |

#### Token Security
**File:** `backend/auth.py`

- Added token revocation blacklist (in-memory, use Redis in production)
- Added explicit expiry validation
- Added `revoke_token()` and `is_token_revoked()` functions

#### Session Management
**File:** `life_agent_flutter/lib/providers/auth_provider.dart`

- Added `ensureValidSession()` method
- Automatic token refresh before expiry (5-minute buffer)

### 3. Dependencies Added

**File:** `backend/requirements.txt`
- `slowapi==0.1.9` - Rate limiting for FastAPI

## Setup Instructions

### 1. Install Python Dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Configure Google OAuth in Supabase

See `GOOGLE_OAUTH_SETUP.md` for detailed instructions.

### 3. Test the Implementation

#### Test Google Sign-in (Web)
1. Run the Flutter app: `flutter run -d chrome`
2. Trigger auth modal (any action requiring auth)
3. Click "Sign in with Google"
4. Complete Google OAuth flow
5. Verify user is authenticated

#### Test Rate Limiting
```bash
# Make 31 rapid requests to chat endpoint
for i in {1..31}; do
  curl -X POST http://localhost:8000/api/chat \
    -H "Authorization: Bearer YOUR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"message": "test"}' &
done
# The 31st request should return 429 Too Many Requests
```

#### Test Security Headers
```bash
curl -I http://localhost:8000/api/system/health
# Should show X-Frame-Options, X-Content-Type-Options, etc.
```

## Security Best Practices Implemented

| Threat | Protection |
|--------|------------|
| CSRF | State parameter in OAuth (handled by Supabase) |
| Token theft | Secure storage (Keychain/Keystore) |
| Replay attacks | PKCE flow (handled by Supabase) |
| MITM | HTTPS required |
| Session hijacking | Short-lived tokens + refresh rotation |
| Brute force | Rate limiting on auth endpoints |
| Clickjacking | X-Frame-Options header |
| XSS | CSP + X-XSS-Protection headers |
| MIME sniffing | X-Content-Type-Options header |

## Production Checklist

Before deploying to production:

- [ ] Configure Google OAuth in Supabase dashboard
- [ ] Set `SUPABASE_JWT_SECRET` in backend `.env`
- [ ] Use Redis for token revocation blacklist
- [ ] Configure proper CORS origins (not `*`)
- [ ] Enable HTTPS on all endpoints
- [ ] Verify OAuth consent screen with Google
- [ ] Set up monitoring for rate limit violations
- [ ] Configure secure cookie settings

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                        Flutter App                            │
│  ┌────────────────┐    ┌────────────────┐                    │
│  │  Auth Modal    │    │  Auth Provider │                    │
│  │  - Email/Pass  │    │  - Session     │                    │
│  │  - Google OAuth│    │  - Token Refr  │                    │
│  └───────┬────────┘    └───────┬────────┘                    │
└──────────┼─────────────────────┼──────────────────────────────┘
           │                     │
           │ OAuth Flow          │ API Calls (JWT)
           ▼                     ▼
┌─────────────────────┐  ┌──────────────────────────────────────┐
│   Google OAuth      │  │           FastAPI Backend            │
│   - User auth       │  │  ┌────────────────────────────────┐  │
│   - Returns code    │  │  │ Security Middleware            │  │
└──────────┬──────────┘  │  │ - Rate limiting                │  │
           │             │  │ - Security headers             │  │
           ▼             │  │ - Token validation             │  │
┌─────────────────────┐  │  └────────────────────────────────┘  │
│    Supabase Auth    │  │                                      │
│  - Exchange code    │  │  ┌────────────────────────────────┐  │
│  - Issue JWT        │  │  │ Protected Routes               │  │
│  - Session mgmt     │  │  │ - /api/chat (30/min)           │  │
└─────────────────────┘  │  │ - /api/adaptive/plans (10/min) │  │
                         │  └────────────────────────────────┘  │
                         └──────────────────────────────────────┘
```
