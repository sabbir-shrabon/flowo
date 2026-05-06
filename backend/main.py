from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# ── Active routers ──
from backend.routers.chat import router as chat_router
from backend.routers.conversations import router as conversations_router
from backend.routers.system import router as system_router
from backend.adaptive.routes.router import router as adaptive_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # No cron scheduler needed — deep review is now trigger-based (milestone + failure threshold)
    yield


app = FastAPI(title="Life Agent API", separate_input_output_schemas=False, lifespan=lifespan)

@app.exception_handler(RuntimeError)
async def runtime_error_handler(request: Request, exc: RuntimeError):
    """Catch Supabase/Internal errors and return them as JSON with a specific message."""
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc)},
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Active routes ──
app.include_router(chat_router)
app.include_router(conversations_router)
app.include_router(system_router)
app.include_router(adaptive_router)

