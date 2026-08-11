PROVIDER_REGISTRY = {
    "openai": {
        "label": "OpenAI",
        "required_fields": ["api_key", "model"],
        "optional_fields": ["base_url", "organization_id"],
        "default_model": "gpt-4o-mini",
        "models": ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1-mini", "o3-mini"],
        "auth_type": "bearer",
        "base_url": "https://api.openai.com/v1",
        "validate_endpoint": "/models",
    },
    "mistral": {
        "label": "Mistral",
        "required_fields": ["api_key", "model"],
        "optional_fields": ["agent_id"],
        "default_model": "mistral-small-latest",
        "models": ["mistral-small-latest", "mistral-medium-latest", "mistral-large-latest", "pixtral-large-latest"],
        "auth_type": "bearer",
        "base_url": "https://api.mistral.ai/v1",
        "validate_endpoint": "/models",
    },
    "gemini": {
        "label": "Google Gemini",
        "required_fields": ["api_key", "model"],
        "optional_fields": [],
        "default_model": "gemini-2.0-flash",
        "models": ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"],
        "auth_type": "query_param",
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
        "validate_endpoint": "/models",
    },
    "groq": {
        "label": "Groq",
        "required_fields": ["api_key", "model"],
        "optional_fields": [],
        "default_model": "llama-3.3-70b-versatile",
        "models": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"],
        "auth_type": "bearer",
        "base_url": "https://api.groq.com/openai/v1",
        "validate_endpoint": "/models",
    },
    "ollama": {
        "label": "Ollama (Local)",
        "required_fields": ["model", "base_url"],
        "optional_fields": [],
        "default_model": "llama3",
        "models": [],  # User-defined
        "auth_type": "none",
        "base_url": "http://localhost:11434",
        "validate_endpoint": "/api/tags",
    },
}

def get_provider_config(provider_name: str) -> dict | None:
    return PROVIDER_REGISTRY.get(provider_name.lower())
