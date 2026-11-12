"""Minimal OpenAI-compatible chat client (AnyModel and similar gateways).

Configuration (environment, never committed):
  AI_BASE_URL         default https://anymodel.org/v1
  AI_API_KEY_USER     key for the user-facing navigator
  AI_API_KEY_ADMIN    key for admin tools (falls back to the user key)
  AI_MODEL_USER       default am/gpt-oss-20b
  AI_MODEL_ADMIN      default am/nemotron-3-ultra-550b-a55b
  AI_MODEL_FALLBACK   default am/nemotron-3.5-lightning-30b-a3b
  AI_REASONING_EFFORT optional (low|medium|high): sent as reasoning_effort to cut "thinking" time
"""
from __future__ import annotations

import logging
import os
import time

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
    max_tokens: int = 1200,
    temperature: float = 0.2,
    timeout: float = 45.0,
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
    effort = (_env("AI_REASONING_EFFORT") or "low").lower()
    if effort in {"low", "medium", "high"} and not _no_effort.get(payload["model"]):
        payload["reasoning_effort"] = effort
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
    except AIError as exc:
        # A model that rejects reasoning_effort: remember it and retry once without the parameter.
        if "reasoning_effort" in payload and str(exc).startswith("HTTP 400") and "reason" in str(exc).lower():
            _no_effort[payload["model"]] = True
            return await chat(messages, role=role, model=payload["model"], tools=tools, max_tokens=max_tokens,
                              temperature=temperature, timeout=timeout)
        raise
    except Exception as exc:  # network, timeout, bad JSON
        raise AIError(type(exc).__name__) from exc
    try:
        choice = body["choices"][0]
        message = choice["message"]
    except (KeyError, IndexError, TypeError) as exc:
        raise AIError("malformed response") from exc
    if not str(message.get("content") or "").strip() and not message.get("tool_calls"):
        # Reasoning models can spend the whole budget on thinking and return no text.
        if choice.get("finish_reason") == "length" and max_tokens < MAX_RETRY_TOKENS:
            # The model thought for the whole budget: retry once with a much bigger one instead of failing the user.
            return await chat(messages, role=role, model=payload["model"], tools=tools,
                              max_tokens=min(max_tokens * 4, MAX_RETRY_TOKENS), temperature=temperature, timeout=timeout)
        raise AIError("token budget used up by reasoning" if choice.get("finish_reason") == "length" else "empty answer")
    return message


MAX_RETRY_TOKENS = 4000
_no_effort: dict[str, bool] = {}
# Circuit breaker: when the primary model just timed out or errored, the next requests go straight to
# the fallback for a few minutes instead of making every user wait for the full timeout again.
PRIMARY_COOLDOWN = 180.0
PRIMARY_TIMEOUT = 12.0
_primary_down_until: dict[tuple[str, str], float] = {}


_fallback_bad_until: dict[str, float] = {}
FALLBACK_COOLDOWN = 600.0


async def chat_with_fallback(messages: list[dict], *, role: str = "user", **kwargs) -> dict:
    """Primary model first with a short slice of the budget, then the fallback. If the fallback itself is broken
    (e.g. HTTP 404 model_not_found), the slow primary gets the full budget instead of the user getting an error."""
    primary_model = kwargs.get("model") or model_for(role)
    fallback = fallback_model()
    key = (role, primary_model)
    total = float(kwargs.get("timeout", 45.0))
    now = time.monotonic()
    fallback_ok = fallback != primary_model and now >= _fallback_bad_until.get(fallback, 0.0)
    if not fallback_ok:
        return await chat(messages, role=role, **kwargs)
    if now < _primary_down_until.get(key, 0.0):
        try:
            return await chat(messages, role=role, **{**kwargs, "model": fallback})
        except AIError as exc:
            _fallback_bad_until[fallback] = time.monotonic() + FALLBACK_COOLDOWN
            logger.warning("AI fallback model %s failed (%s); using the primary only for a while", fallback, exc)
            return await chat(messages, role=role, **kwargs)
    try:
        # Primary gets a short slice of the budget; the fallback keeps the rest.
        return await chat(messages, role=role, **{**kwargs, "timeout": min(total, PRIMARY_TIMEOUT)})
    except AIError as primary:
        _primary_down_until[key] = time.monotonic() + PRIMARY_COOLDOWN
        logger.warning("AI primary model failed (%s); using fallback for %ds", primary, int(PRIMARY_COOLDOWN))
        try:
            return await chat(messages, role=role, **{**kwargs, "model": fallback})
        except AIError as exc:
            _fallback_bad_until[fallback] = time.monotonic() + FALLBACK_COOLDOWN
            logger.warning("AI fallback model %s failed (%s); retrying the primary with the full budget", fallback, exc)
            return await chat(messages, role=role, **kwargs)
