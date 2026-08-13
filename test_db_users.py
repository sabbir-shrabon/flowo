import os
import sys
import asyncio

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from backend.lib.db import get_supabase_client

from backend.lib.crypto import decrypt_key

supabase = get_supabase_client()
res = supabase.table("users").select("id, llm_provider, llm_api_key").execute()
data = res.data if hasattr(res, 'data') else (res[1] if isinstance(res, tuple) else res)
for r in data:
    enc_key = r.get('llm_api_key')
    dec_key = decrypt_key(enc_key) if enc_key else None
    if dec_key == "":
        print(f"Empty string key found for user {r['id']}")
    elif dec_key is not None:
        print(f"Valid key for user {r['id']}")
    else:
        print(f"No key (None) for user {r['id']}")

