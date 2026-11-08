import asyncio, logging
from aiohttp import ClientSession, ClientTimeout
from config import PLUGIN_API_URL, PLUGIN_API_KEY

log = logging.getLogger(__name__)

async def plugin_post(path: str, payload: dict) -> tuple[bool, dict]:
    if not PLUGIN_API_URL:
        return False, {"error": "PLUGIN_API_URL_NOT_CONFIGURED"}
    headers = {"Content-Type": "application/json"}
    if PLUGIN_API_KEY:
        headers["X-API-Key"] = PLUGIN_API_KEY
    try:
        timeout = ClientTimeout(total=8)
        async with ClientSession(timeout=timeout) as session:
            async with session.post(f"{PLUGIN_API_URL}{path}", json=payload, headers=headers) as resp:
                data = await resp.json(content_type=None)
                return resp.status < 300, data if isinstance(data, dict) else {"data": data}
    except Exception as exc:
        log.warning("Plugin API %s failed: %s", path, exc)
        return False, {"error": str(exc)}
