import logging
from cryptography.fernet import Fernet
from backend.config import settings

logger = logging.getLogger(__name__)

def _get_fernet() -> Fernet | None:
    if not getattr(settings, 'encryption_master_key', None):
        logger.error("ENCRYPTION_MASTER_KEY is not set. Encryption/Decryption disabled.")
        return None
    try:
        return Fernet(settings.encryption_master_key.encode("utf-8"))
    except Exception as e:
        logger.error(f"Invalid ENCRYPTION_MASTER_KEY: {e}")
        return None

def encrypt_key(plain_key: str) -> str | None:
    fernet = _get_fernet()
    if not fernet or not plain_key:
        return None
    return fernet.encrypt(plain_key.encode("utf-8")).decode("utf-8")

def decrypt_key(encrypted_key: str) -> str | None:
    fernet = _get_fernet()
    if not fernet or not encrypted_key:
        return None
    try:
        return fernet.decrypt(encrypted_key.encode("utf-8")).decode("utf-8")
    except Exception as e:
        logger.error(f"Failed to decrypt key: {e}")
        return None

def mask_key(plain_key: str) -> str | None:
    if not plain_key:
        return None
    if len(plain_key) <= 8:
        return "****"
    return f"{plain_key[:3]}...{plain_key[-4:]}"
