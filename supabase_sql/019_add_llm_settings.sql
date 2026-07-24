-- ═══════════════════════════════════════════════════════════════════════════════
-- Migration: Add LLM settings to users table
-- Description: Adds columns for llm_provider, llm_model, and encrypted llm_api_key
-- ═══════════════════════════════════════════════════════════════════════════════

ALTER TABLE users
ADD COLUMN IF NOT EXISTS llm_provider text DEFAULT 'mistral',
ADD COLUMN IF NOT EXISTS llm_model text,
ADD COLUMN IF NOT EXISTS llm_api_key text;

-- Add a comment to the table to explain the encryption
COMMENT ON COLUMN users.llm_api_key IS 'API Key for LLM Provider. Stored encrypted via app-level AES-256.';
