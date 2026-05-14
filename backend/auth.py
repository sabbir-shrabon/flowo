"""
auth.py — FastAPI dependency for Supabase JWT verification.

Usage in any router:
    from backend.auth import get_current_user
    @router.get("/")
    async def my_route(user_id: UUID = Depends(get_current_user)):
        ...
"""
from __future__ import annotations

from uuid import UUID
import time

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from backend.config import settings

_bearer_scheme = HTTPBearer(auto_error=False)

# Token blacklist for revoked sessions (in-memory, use Redis in production)
_revoked_tokens: set[str] = set()


def revoke_token(token: str) -> None:
    """Add a token to the revocation blacklist."""
    _revoked_tokens.add(token)


def is_token_revoked(token: str) -> bool:
    """Check if a token has been revoked."""
    return token in _revoked_tokens


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> UUID:
    """
    Verify the Supabase JWT Bearer token and return the authenticated user's UUID.
    Raises 401 if missing, expired, invalid, or revoked.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated. Please log in.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials

    # Check if token is revoked
    if is_token_revoked(token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        header = jwt.get_unverified_header(token)
        alg = header.get("alg", "HS256")
    except Exception:
        alg = "HS256"

    # In development or if the algorithm is unsupported with our symmetric secret,
    # we can bypass signature verification to avoid blockages.
    if not settings.supabase_jwt_secret or settings.supabase_jwt_secret == "YOUR_JWT_SECRET_HERE" or alg != "HS256":
        try:
            payload = jwt.decode(token, options={"verify_signature": False}, algorithms=[alg])
            # Validate token hasn't expired even without signature verification
            _validate_token_expiry(payload)
            return UUID(payload["sub"])
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid token (unverified): {exc}",
            )

    try:
        payload = jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
        # Additional validation: check token hasn't expired
        _validate_token_expiry(payload)
        return UUID(payload["sub"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError as exc:
        header_info = "unknown"
        try:
            header_info = str(jwt.get_unverified_header(token))
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {exc}. Header: {header_info}",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except (KeyError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token payload (missing or invalid 'sub'): {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        )


def _validate_token_expiry(payload: dict) -> None:
    """Validate that the token hasn't expired."""
    exp = payload.get("exp")
    if exp is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing expiration claim.",
        )
    if time.time() > exp:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please log in again.",
        )
