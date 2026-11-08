from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from pathlib import Path
from typing import Any

from aiogram import BaseMiddleware, Router
from aiogram.types import CallbackQuery, Message

from db.rpc import bot_get_public_module_states

logger = logging.getLogger(__name__)

# The repository registry is the source of truth for module dependencies.
_REGISTRY_PATH = Path(__file__).resolve().parents[2] / "modules" / "registry.json"
try:
    _registry = json.loads(_REGISTRY_PATH.read_text(encoding="utf-8"))
    _MODULE_DEPENDENCIES: dict[str, tuple[str, ...]] = {
        str(module["id"]): tuple(str(value) for value in module.get("dependsOn", []))
        for module in _registry["modules"]
        if isinstance(module, dict) and isinstance(module.get("id"), str)
    }
except (OSError, ValueError, KeyError, TypeError) as exc:
    logger.error("Module registry unavailable; bot feature gates will fail closed: %s", exc)
    _MODULE_DEPENDENCIES = {}

_STATE_CACHE: dict[str, bool] | None = None
_STATE_CACHE_EXPIRES_AT = 0.0
_STATE_CACHE_LOCK = asyncio.Lock()
_STATE_TTL_SECONDS = 15.0
_ERROR_TTL_SECONDS = 5.0


async def _get_module_states() -> dict[str, bool] | None:
    global _STATE_CACHE, _STATE_CACHE_EXPIRES_AT

    now = time.monotonic()
    if now < _STATE_CACHE_EXPIRES_AT:
        return _STATE_CACHE

    async with _STATE_CACHE_LOCK:
        now = time.monotonic()
        if now < _STATE_CACHE_EXPIRES_AT:
            return _STATE_CACHE

        result = await bot_get_public_module_states()
        if result.error or not isinstance(result.data, list):
            logger.warning("Could not read module state; feature access is temporarily blocked")
            _STATE_CACHE = None
            _STATE_CACHE_EXPIRES_AT = time.monotonic() + _ERROR_TTL_SECONDS
            return None

        states: dict[str, bool] = {}
        for row in result.data:
            if not isinstance(row, dict):
                continue
            module_id = row.get("module_id")
            enabled = row.get("enabled")
            if isinstance(module_id, str) and isinstance(enabled, bool):
                states[module_id] = enabled

        # An empty or malformed response must not accidentally enable features.
        if not states:
            logger.warning("Module state RPC returned no valid states; feature access is temporarily blocked")
            _STATE_CACHE = None
            _STATE_CACHE_EXPIRES_AT = time.monotonic() + _ERROR_TTL_SECONDS
            return None

        _STATE_CACHE = states
        _STATE_CACHE_EXPIRES_AT = time.monotonic() + _STATE_TTL_SECONDS
        return states


def _is_effectively_enabled(module_id: str, states: dict[str, bool]) -> bool:
    if module_id not in _MODULE_DEPENDENCIES or states.get(module_id) is not True:
        return False

    def visit(current: str, visiting: frozenset[str]) -> bool:
        if current in visiting or current not in _MODULE_DEPENDENCIES:
            return False
        if states.get(current) is not True:
            return False
        next_visiting = visiting | {current}
        return all(
            visit(dependency, next_visiting)
            for dependency in _MODULE_DEPENDENCIES[current]
        )

    return visit(module_id, frozenset())


async def is_module_effectively_enabled(module_id: str) -> bool:
    """Return the effective state, failing closed if state cannot be verified."""
    states = await _get_module_states()
    if states is None:
        return False
    return _is_effectively_enabled(module_id, states)


class ModuleGateMiddleware(BaseMiddleware):
    def __init__(self, module_id: str) -> None:
        self.module_id = module_id

    async def __call__(self, handler, event: Any, data: dict[str, Any]) -> Any:
        if await is_module_effectively_enabled(self.module_id):
            return await handler(event, data)

        notice = "Эта функция временно недоступна: модуль отключён или нет связи с PRISMA."
        try:
            if isinstance(event, Message):
                await event.answer(notice)
            elif isinstance(event, CallbackQuery):
                await event.answer(notice, show_alert=True)
        except Exception:
            # A missing/unavailable reply must not cause a blocked handler to run.
            logger.debug("Could not send disabled-module notice", exc_info=True)
        return None



class ModuleDispatchMiddleware(BaseMiddleware):
    """Gate mixed routers using explicit command/callback ownership maps."""

    def __init__(
        self,
        command_modules: dict[str, str],
        callback_modules: dict[str, str],
        text_patterns: tuple[tuple[str, str], ...] = (),
    ) -> None:
        self.command_modules = {
            name.casefold().lstrip("/"): module_id
            for name, module_id in command_modules.items()
        }
        self.callback_modules = tuple(callback_modules.items())
        self.text_patterns = tuple(
            (re.compile(pattern, re.IGNORECASE), module_id)
            for pattern, module_id in text_patterns
        )

    def _module_for(self, event: Any) -> str | None:
        if isinstance(event, Message):
            text = (event.text or event.caption or "").strip()
            if not text:
                return None

            first = text.split(maxsplit=1)[0]
            if first.startswith("/"):
                # Argument-sensitive patterns (for example /who inactive) take
                # precedence over the command's default module mapping.
                for pattern, module_id in self.text_patterns:
                    if pattern.fullmatch(text):
                        return module_id
                command = first[1:].split("@", 1)[0].casefold()
                return self.command_modules.get(command)

            for pattern, module_id in self.text_patterns:
                if pattern.fullmatch(text):
                    return module_id
            return None

        if isinstance(event, CallbackQuery):
            data = event.data or ""
            for selector, module_id in self.callback_modules:
                if selector.endswith("*"):
                    if data.startswith(selector[:-1]):
                        return module_id
                elif data == selector:
                    return module_id
        return None

    async def __call__(self, handler, event: Any, data: dict[str, Any]) -> Any:
        module_id = self._module_for(event)
        if module_id is None or await is_module_effectively_enabled(module_id):
            return await handler(event, data)

        notice = "Эта функция временно недоступна: модуль отключён или нет связи с PRISMA."
        try:
            if isinstance(event, Message):
                await event.answer(notice)
            elif isinstance(event, CallbackQuery):
                await event.answer(notice, show_alert=True)
        except Exception:
            logger.debug("Could not send disabled-module notice", exc_info=True)
        return None


def attach_module_dispatch_gate(
    router: Router,
    *,
    command_modules: dict[str, str],
    callback_modules: dict[str, str],
    text_patterns: tuple[tuple[str, str], ...] = (),
) -> None:
    """Gate only mapped handlers in mixed routers; unmapped core handlers remain available."""
    gate = ModuleDispatchMiddleware(command_modules, callback_modules, text_patterns)
    router.message.middleware(gate)
    router.callback_query.middleware(gate)

def attach_module_gate(router: Router, module_id: str) -> None:
    """Gate matched message and callback handlers without blocking other routers."""
    gate = ModuleGateMiddleware(module_id)
    router.message.middleware(gate)
    router.callback_query.middleware(gate)
