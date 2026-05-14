# Google OAuth Setup Guide

This guide explains how to set up Google OAuth for the Life Agent app.

## Overview

The app uses Supabase Auth with Google OAuth provider. The flow works as follows:

```
┌─────────┐      1. Click "Sign in with Google"     ┌─────────┐
│   App   │ ──────────────────────────────────────► │  Google │
│         │      2. User grants permission          │         │
│         │ ◄────────────────────────────────────── │         │
│         │      3. Auth code returned              │         │
│         │                                         └─────────┘
│         │      4. Exchange code for tokens        ┌─────────┐
│         │ ──────────────────────────────────────► │ Supabase│
│         │      5. JWT tokens returned             │         │
│         │ ◄────────────────────────────────────── │         │
└─────────┘                                         └─────────┘
```

## Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable "Google+ API" or "People API" for user profile data

## Step 2: Configure OAuth Consent Screen

1. Go to **APIs & Services** → **OAuth consent screen**
2. Choose **External** user type (unless you have a Google Workspace)
3. Fill in required fields:
   - **App name**: Life Agent
   - **User support email**: your email
   - **Developer contact email**: your email
4. Add scopes:
   - `email` (required)
   - `profile` (required)
   - `openid` (required)
5. Add test users (for development)
6. Submit for verification (optional for development)

## Step 3: Create OAuth 2.0 Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Choose **Web application**
4. Configure authorized redirect URIs:

### For Supabase Cloud:
```
https://<your-project-ref>.supabase.co/auth/v1/callback
```

### For Local Development:
```
http://localhost:54321/auth/v1/callback
```

5. Copy the **Client ID** and **Client Secret**

## Step 4: Configure Supabase

1. Go to your Supabase project dashboard
2. Navigate to **Authentication** → **Providers**
3. Find **Google** and enable it
4. Paste your **Client ID** and **Client Secret** from Google Cloud
5. Save the configuration

## Step 5: Configure Deep Links (Mobile)

For mobile apps, you need to configure deep links:

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="io.supabase.lifeagent" />
    </intent-filter>
</activity>
```

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>io.supabase.lifeagent</string>
        </array>
    </dict>
</array>
```

### Web

No additional configuration needed. Supabase handles web OAuth with popup or redirect.

## Security Features Implemented

### Frontend (Flutter)
- **PKCE Flow**: Supabase automatically uses PKCE for OAuth, preventing authorization code interception attacks
- **Secure Token Storage**: Tokens stored in secure storage (Keychain on iOS, Keystore on Android)
- **Session Refresh**: Automatic token refresh before expiry
- **State Parameter**: CSRF protection built into Supabase OAuth

### Backend (FastAPI)
- **Rate Limiting**: 60 requests/minute per IP (configurable)
- **Security Headers**:
  - `X-Frame-Options: DENY` - Prevents clickjacking
  - `X-Content-Type-Options: nosniff` - Prevents MIME sniffing
  - `X-XSS-Protection: 1; mode=block` - XSS protection
  - `Content-Security-Policy: default-src 'self'` - CSP
- **Token Validation**: JWT signature verification + expiry check
- **Token Revocation**: Support for revoking compromised tokens

## Testing

1. Run the app
2. Click "Sign in with Google"
3. Complete Google OAuth flow
4. Verify user is authenticated

## Troubleshooting

### "Invalid redirect URI"
- Ensure the redirect URI in Google Cloud Console matches Supabase exactly
- Check for trailing slashes

### "OAuth client not found"
- Verify Client ID and Client Secret in Supabase dashboard
- Ensure Google Cloud project is active

### "Access blocked" on mobile
- Add your email as a test user in Google Cloud Console
- Or publish your app for production use

## Production Checklist

- [ ] OAuth consent screen verified by Google
- [ ] Production redirect URIs configured
- [ ] Rate limiting configured appropriately
- [ ] Token revocation using Redis (not in-memory)
- [ ] HTTPS enabled on all endpoints
- [ ] Secure session cookie settings
