-- Migration to add additional LLM configuration fields for BYOK users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS llm_base_url TEXT,
  ADD COLUMN IF NOT EXISTS llm_agent_id TEXT,
  ADD COLUMN IF NOT EXISTS llm_organization_id TEXT;
