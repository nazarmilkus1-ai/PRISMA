"""Second AI that reads the agent's diff and gives a verdict. It advises the human; it never merges."""
from __future__ import annotations

import json
import logging
import re

from services.ai import client

from . import github

logger = logging.getLogger(__name__)

PROMPT = ("Ты строгий ревьюер кода проекта PRISMA (Python/aiogram бот, Next.js сайт и панель, Supabase, плагин Paper). "
          "Тебе дают diff, написанный другим ИИ-агентом. Ищи: баги, утечки секретов, опасные действия, слом безопасности (RPC только service_role), "
          "поломку существующего. Ответ строго JSON: {\"verdict\":\"OK|RISKS|BLOCK\",\"notes\":\"до 300 символов по-русски, простыми словами для не программиста, без названий файлов\",\"plain\":\"1-2 коротких предложения по-русски: что изменится для игроков или админов Minecraft-сообщества, без терминов и названий файлов\"}. "
          "BLOCK только за серьёзную опасность или явную поломку.")


def parse_verdict(text: str) -> dict:
    match = re.search(r"\{.*\}", text or "", re.S)
    try:
        data = json.loads(match.group(0)) if match else {}
    except ValueError:
        data = {}
    verdict = str(data.get("verdict") or "").upper()
    if verdict not in {"OK", "RISKS", "BLOCK"}:
        return {"verdict": "RISKS", "notes": "Ревьюер не дал чёткий ответ — проверьте diff вручную."}
    return {"verdict": verdict, "notes": str(data.get("notes") or "")[:400], "plain": str(data.get("plain") or "")[:400]}


async def review(head_sha: str) -> dict:
    if not client.is_configured("reviewer"):
        return {"verdict": "RISKS", "notes": "Ревьюер не настроен."}
    from . import config
    diff = await github.compare(config.BASE_BRANCH, head_sha)
    if diff.get("error"):
        return {"verdict": "RISKS", "notes": "Не удалось получить diff."}
    try:
        msg = await client.chat([{"role": "system", "content": PROMPT}, {"role": "user", "content": str(diff.get("diff"))[:24_000]}],
                                role="reviewer", max_tokens=700, timeout=90.0)
    except client.AIError as exc:
        logger.warning("reviewer failed: %s", exc)
        return {"verdict": "RISKS", "notes": "Ревьюер недоступен."}
    return parse_verdict(str(msg.get("content") or ""))
