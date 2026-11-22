"""Long-term memory of the agent: pinned core, full-text recall, daily consolidation of old notes."""
from __future__ import annotations

import logging
import re

from db import rpc
from services.ai import client

logger = logging.getLogger(__name__)
_WORD = re.compile(r"[\w]{4,}", re.U)


def _rows(result) -> list[dict]:
    return [r for r in (result.data or []) if isinstance(r, dict)] if not result.error and isinstance(result.data, list) else []


def _line(m: dict) -> str:
    pin = "📌" if m.get("pinned") else ""
    return f"- #{m.get('id')} [{m.get('kind')}/{m.get('importance')}]{pin} {str(m.get('body') or '')[:400]}"


def query_from(*texts: str, limit: int = 8) -> str:
    words: list[str] = []
    for text in texts:
        for w in _WORD.findall((text or "").lower()):
            if w not in words:
                words.append(w)
    return " or ".join(words[:limit])


async def build_context(goal: dict | None, inbox: list[dict]) -> str:
    core = _rows(await rpc.bot_agent_mem_core(30))
    seed = query_from(*( [goal.get("title", ""), goal.get("expected", "")] if goal else []), *[m.get("text", "") for m in inbox[-5:]])
    recalled = _rows(await rpc.bot_agent_mem_search(seed, 10)) if seed else []
    seen = {m.get("id") for m in core}
    parts = ["## Главная память (закреплённое и самое важное)"] + ([_line(m) for m in core] or ["(пусто)"])
    extra = [m for m in recalled if m.get("id") not in seen]
    if extra:
        parts += ["## Вспомнилось по теме"] + [_line(m) for m in extra]
    return "\n".join(parts)


async def consolidate() -> int:
    """Merge old low-importance notes into one summary so memory stays sharp. Returns how many notes were folded."""
    old = _rows(await rpc.bot_agent_mem_old(7, 60))
    if len(old) < 15:
        return 0
    text = "\n".join(f"#{m['id']} [{m.get('kind')}] {str(m.get('body'))[:300]}" for m in old)
    try:
        msg = await client.chat(
            [{"role": "system", "content": "Ты сжимаешь заметки своей памяти. Сохрани все факты, решения, уроки, предпочтения людей и "
                                           "идеи, убери дубли и мелочи. Ответ: только итоговый текст (до 1400 символов), по-русски."},
             {"role": "user", "content": text[:12_000]}],
            role="agent", model=client.agent_models()[0], max_tokens=900, timeout=90.0)
    except client.AIError as exc:
        logger.warning("memory consolidation skipped: %s", exc)
        return 0
    body = str(msg.get("content") or "").strip()[:1450]
    if len(body) < 40:
        return 0
    res = await rpc.bot_agent_mem_replace([m["id"] for m in old], "fact", body, 4)
    return 0 if res.error else len(old)
