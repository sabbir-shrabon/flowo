import os
import sys

# Add project root to sys.path so we can import backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from backend.lib.llm_client import send_chat
import uuid

# UUID of user who has use_managed_key = False
user_id = uuid.UUID("c819e40a-34b0-4f70-9caf-034a89a54f9f")

try:
    print(f"Testing chat for existing user without BYOK: {user_id}")
    messages = [{"role": "user", "content": "Hello! Say just the word ping."}]
    system_prompt = "You are a helpful assistant."
    resp = send_chat(user_id, messages, system=system_prompt)
    print("SUCCESS:", resp)
except Exception as e:
    print("FAILED:", e)
