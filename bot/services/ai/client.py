"""Minimal OpenAI-compatible chat client (AnyModel and similar gateways).

Configuration (environment, never committed):
  AI_BASE_URL         default https://anymodel.org/v1
  AI_API_KEY_USER     key for the user-facing navigator
  AI_API_KEY_ADMIN    key for admin tools (falls back to the user key)
  AI_MODEL_USER       default am/gpt-oss-20b
  AI_MODEL_ADMIN      default am/nemotron-3-ultra-550b-a55b
  AI_MODEL_FALLBACK   default am/nemotron-3.5-lightning-30b-a3b
"""
from __future__ import annotations

import logging
import os

import aiohttp

logger = logging.getLogger(__name__)


class AIError(Exception):
    pass


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def base_url() -> str:
    return (_env("AI_BASE_URL") or "https://anymodel.org/v1").rstrip("/")


def key_for(role: str) -> str:
    user_key = _env("AI_API_KEY_USER")
    return (_env("AI_API_KEY_ADMIN") or user_key) if role == "admin" else user_key


def model_for(role: str) -> str:
    if role == "admin":
        return _env("AI_MODEL_ADMIN") or "am/nemotron-3-ultra-550b-a55b"
    return _env("AI_MODEL_USER") or "am/gpt-oss-20b"


def fallback_model() -> str:
    return _env("AI_MODEL_FALLBACK") or "am/nemotron-3.5-lightning-30b-a3b"


def is_configured(role: str = "user") -> bool:
    return bool(key_for(role))


async def chat(
    messages: list[dict],
    *,
    role: str = "user",
    model: str | None = None,
    tools: list[dict] | None = None,
    max_tokens: int = 500,
    temperature: float = 0.2,
    timeout: float = 30.0,
) -> dict:
    """Return the assistant message dict. Raises AIError on any failure."""
    key = key_for(role)
    if not key:
        raise AIError("AI is not configured")
    payload: dict = {
        "model": model or model_for(role),
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": False,
    }
    if tools:
        payload["tools"] = tools
        payload["tool_choice"] = "auto"
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=timeout)) as session:
            async with session.post(
                f"{base_url()}/chat/completions",
                json=payload,
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            ) as response:
                body = await response.json(content_type=None)
                if response.status >= 400:
                    # Log status and provider error text only: never headers or keys.
                    detail = (body.get("error") if isinstance(body, dict) else None) or ""
                    raise AIError(f"HTTP {response.status}: {str(detail)[:200]}")
    except AIError:
        raise
    except Exception as exc:  # network, timeout, bad JSON
        raise AIError(type(exc).__name__) from exc
    try:
        return body["choices"][0]["message"]
    except (KeyError, IndexError, TypeError) as exc:
        raise AIError("malformed response") from exc


async def chat_with_fallback(messages: list[dict], *, role: str = "user", **kwargs) -> dict:
    try:
        return await chat(messages, role=role, **kwargs)
    except AIError as primary:
        logger.warning("AI primary model failed (%s); trying fallback", primary)
        return await chat(messages, role=role, model=fallback_model(), **kwargs)
