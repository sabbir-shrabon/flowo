import pytest
from unittest.mock import patch, MagicMock
from uuid import uuid4

from backend.lib.crypto import encrypt_key, decrypt_key, mask_key
from backend.lib.llm_client import get_client_for_user, clear_user_cache
from backend.config import settings

def test_crypto_round_trip():
    # Ensure master key is set
    original_key = getattr(settings, "encryption_master_key", None)
    if not original_key:
        from cryptography.fernet import Fernet
        settings.encryption_master_key = Fernet.generate_key().decode("utf-8")
        
    plain_key = "sk-test1234567890"
    encrypted = encrypt_key(plain_key)
    
    assert encrypted is not None
    assert encrypted != plain_key
    
    decrypted = decrypt_key(encrypted)
    assert decrypted == plain_key
    
    assert mask_key(plain_key) == "sk-...7890"

@patch("backend.lib.llm_client.get_supabase_client")
def test_fallback_to_env_var(mock_get_supabase):
    mock_supabase = MagicMock()
    mock_get_supabase.return_value = mock_supabase
    
    # Mock empty db response
    mock_supabase.table().select().eq().execute.return_value = (None, [])
    
    user_id = uuid4()
    clear_user_cache(user_id)
    
    # Temporarily set env var
    settings.llm_provider = "openai"
    settings.openai_model = "gpt-test"
    settings.openai_api_key = "sk-env-key"
    
    client = get_client_for_user(user_id)
    
    assert client["provider"] == "openai"
    assert client["model"] == "gpt-test"
    assert client["api_key"] == "sk-env-key"

@patch("backend.lib.llm_client.get_supabase_client")
def test_user_isolation(mock_get_supabase):
    mock_supabase = MagicMock()
    mock_get_supabase.return_value = mock_supabase
    
    user1 = uuid4()
    user2 = uuid4()
    
    encrypted_key1 = encrypt_key("sk-user1")
    encrypted_key2 = encrypt_key("sk-user2")
    
    def side_effect(col, uid_str):
        mock_eq = MagicMock()
        if uid_str == str(user1):
            mock_eq.execute.return_value = (None, [{"llm_provider": "openai", "llm_model": "gpt-4", "llm_api_key": encrypted_key1}])
        elif uid_str == str(user2):
            mock_eq.execute.return_value = (None, [{"llm_provider": "gemini", "llm_model": "gemini-pro", "llm_api_key": encrypted_key2}])
        else:
            mock_eq.execute.return_value = (None, [])
        return mock_eq

    # Setup mock chain: table().select().eq()
    mock_select = MagicMock()
    mock_select.eq.side_effect = side_effect
    mock_table = MagicMock()
    mock_table.select.return_value = mock_select
    mock_supabase.table.return_value = mock_table

    clear_user_cache(user1)
    clear_user_cache(user2)
    
    client1 = get_client_for_user(user1)
    client2 = get_client_for_user(user2)
    
    assert client1["provider"] == "openai"
    assert client1["api_key"] == "sk-user1"
    
    assert client2["provider"] == "gemini"
    assert client2["api_key"] == "sk-user2"
