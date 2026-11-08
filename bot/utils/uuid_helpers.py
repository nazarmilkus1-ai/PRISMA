import base64
import binascii
import uuid

def encode_uuid(value: str) -> str:
    raw = uuid.UUID(str(value)).bytes
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")

def decode_uuid(value: str) -> str:
    try:
        padded = value + "=" * (-len(value) % 4)
        raw = base64.urlsafe_b64decode(padded)
        if len(raw) != 16:
            raise ValueError("Invalid UUID length")
        return str(uuid.UUID(bytes=raw))
    except (ValueError, TypeError, binascii.Error) as exc:
        raise ValueError("Invalid UUID encoding") from exc