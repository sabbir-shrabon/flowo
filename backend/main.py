from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

try:
    from slowapi import Limiter, _rate_limit_exceeded_handler
    from slowapi.errors import RateLimitExceeded
    from slowapi.util import get_remote_address
except ImportError:
    Limiter = None
    _rate_limit_exceeded_handler = None
    RateLimitExceeded = None
    get_remote_address = None

from backend.adaptive.routes.router import router as adaptive_router
from backend.config import settings
from backend.routers.chat import router as chat_router
from backend.routers.conversations import router as conversations_router
from backend.routers.system import router as system_router
from backend.routers.settings import router as settings_router

limiter = Limiter(key_func=get_remote_address) if Limiter and get_remote_address else None


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(
    title="Life Agent API",
    separate_input_output_schemas=False,
    lifespan=lifespan,
)

app.state.limiter = limiter
if limiter and RateLimitExceeded and _rate_limit_exceeded_handler:
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    return response


@app.exception_handler(RuntimeError)
async def runtime_error_handler(request: Request, exc: RuntimeError):
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc)},
    )


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["system"])
async def root():
    return {"ok": True, "service": "Life Agent API", "health": "/api/health"}


@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return Response(status_code=204)

app.include_router(chat_router)
app.include_router(conversations_router)
app.include_router(system_router)
app.include_router(adaptive_router)
app.include_router(settings_router)
