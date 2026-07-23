from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from typing import Optional
import os


def _parse_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


class Settings(BaseSettings):
    # Supabase Configuration
    supabase_url: Optional[str] = Field(None, env="SUPABASE_URL")
    supabase_service_role_key: Optional[str] = Field(None, env="SUPABASE_SERVICE_ROLE_KEY")
    supabase_jwt_secret: Optional[str] = Field(None, env="SUPABASE_JWT_SECRET")
    supabase_anon_key: Optional[str] = Field(None, env="SUPABASE_ANON_KEY")

    dev_mode: bool = Field(True, env="DEV_MODE")

    # LLM Provider Configuration
    llm_provider: str = Field("openai", env="LLM_PROVIDER") # 'openai', 'gemini', 'ollama'
    
    openai_api_key: Optional[str] = Field(None, env="OPENAI_API_KEY")
    openai_model: str = Field("gpt-4o-mini", env="OPENAI_MODEL")
    
    gemini_api_key: Optional[str] = Field(None, env="GEMINI_API_KEY")
    gemini_model: str = Field("gemini-2.0-flash", env="GEMINI_MODEL")
    
    ollama_base_url: Optional[str] = Field(None, env="OLLAMA_BASE_URL")
    ollama_model: str = Field("llama3", env="OLLAMA_MODEL")

    groq_api_key: Optional[str] = Field(None, env="GROQ_API_KEY")
    groq_model: str = Field("llama-3.3-70b-versatile", env="GROQ_MODEL")

    mistral_api_key: Optional[str] = Field(None, env="MISTRAL_API_KEY")
    mistral_model: str = Field("mistral-small-latest", env="MISTRAL_MODEL")
    mistral_agent_id: str = Field("ag_019d775d5d3c744fafefd4fbd5c99a66", env="MISTRAL_AGENT_ID")

    cors_origins_raw: str = Field(
        "",
        env="CORS_ORIGINS",
    )
    frontend_url_raw: str = Field(
        "",
        env="FRONTEND_URL",
    )
    cors_origin_regex: str = Field(
        r"https://([a-z0-9-]+\.)*(netlify\.app|vercel\.app)(:\d+)?$|http://localhost(:\d+)?$|http://127\.0\.0\.1(:\d+)?$",
        env="CORS_ORIGIN_REGEX",
    )

    _env_file = os.path.join(os.path.dirname(__file__), ".env")
    model_config = SettingsConfigDict(
        env_file=_env_file if os.path.exists(_env_file) else None,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def cors_origins(self) -> list[str]:
        origins = _parse_csv(self.cors_origins_raw)
        origins.extend(_parse_csv(self.frontend_url_raw))
        return list(dict.fromkeys(origins))

settings = Settings()

