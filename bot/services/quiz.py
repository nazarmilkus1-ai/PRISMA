"""Quiz rounds for chats: the model writes one question, Telegram runs it as a native quiz poll.

Scores live in RAM (reset on restart): a light chat game, not an economy. Questions are validated before
they are posted (4 distinct options, a valid correct index, Telegram length limits).
"""
from __future__ import annotations

import json
import re
import time
from collections import Counter, defaultdict

from services.ai import sanitize
from services.ai.client import AIError, chat_with_fallback, is_configured
from utils.mdhtml import strip_markdown
from utils.rules import RULES

COOLDOWN = 25.0
DAILY_CAP = 40
MAX_TRACKED = 500

_scores: dict[int, Counter] = defaultdict(Counter)
_names: dict[tuple[int, int], str] = {}
_polls: dict[str, dict] = {}
_last: dict[int, float] = {}
_day: dict[int, tuple[int, int]] = {}


def allowed(chat_id: int, now: float | None = None) -> str | None:
    """None when a new round may start, otherwise the reason (for the chat)."""
    now = time.time() if now is None else now
    if now - _last.get(chat_id, 0.0) < COOLDOWN:
        return "Подождите немного перед следующим вопросом."
    day, count = _day.get(chat_id, (int(now // 86400), 0))
    if day == int(now // 86400) and count >= DAILY_CAP:
        return "На сегодня вопросов хватит, продолжим завтра."
    _last[chat_id] = now
    _day[chat_id] = (int(now // 86400), (count if day == int(now // 86400) else 0) + 1)
    return None


def parse(raw: str) -> dict | None:
    match = re.search(r"\{.*\}", raw or "", re.S)
    if not match:
        return None
    try:
        data = json.loads(match.group(0))
    except ValueError:
        return None
    question = str(data.get("question") or "").strip()
    options = [str(o).strip() for o in (data.get("options") or [])]
    correct = data.get("correct")
    if not isinstance(correct, int) or isinstance(correct, bool) or len(options) != 4 or not 0 <= correct <= 3:
        return None
    if not 5 <= len(question) <= 300 or any(not 1 <= len(o) <= 100 for o in options) or len({o.casefold() for o in options}) != 4:
        return None
    return {"question": question, "options": options, "correct": correct,
            "explanation": str(data.get("explanation") or "").strip()[:190] or None}


def _system(topic: str, adult: int) -> str:
    base = (
        "Ты придумываешь ОДИН вопрос викторины для Telegram-чата Minecraft-сообщества. Вопрос должен иметь один бесспорно верный ответ "
        "и три правдоподобных неверных. Не используй спорные или зависящие от версии факты. Ответь ТОЛЬКО JSON: "
        '{"question":"...","options":["...","...","...","..."],"correct":0-3,"explanation":"одна короткая фраза, почему"}. '
        "Вариантов ровно 4, верный ставь на случайное место."
    )
    if topic == "rules":
        base += " Тема: правила сообщества PRISMA. Правила:\n" + "\n".join(f"{t}: {b}" for t, b in RULES) + "\nСпрашивай только по этим правилам."
    else:
        base += " Тема: Minecraft (мобы, крафт, блоки, механики, история игры, редстоун, биомы). Разной сложности."
    if adult:
        base += " Тон вопроса дерзкий и с юмором."
    return base


async def generate(topic: str = "minecraft", adult: int = 0, seen: list[str] | None = None) -> dict | None:
    if not is_configured("user"):
        return None
    avoid = f" Не повторяй эти вопросы: {'; '.join((seen or [])[-8:])}" if seen else ""
    for _ in range(2):
        try:
            message = await chat_with_fallback(
                [{"role": "system", "content": _system(topic, adult) + avoid}, {"role": "user", "content": "Новый вопрос."}],
                role="user", max_tokens=800, timeout=40, temperature=0.9)
        except AIError:
            return None
        quiz = parse(str(message.get("content") or ""))
        if quiz:
            return quiz
    return None


_recent: dict[int, list[str]] = defaultdict(list)


def remember_question(chat_id: int, question: str) -> None:
    _recent[chat_id] = (_recent[chat_id] + [question[:80]])[-10:]


def recent(chat_id: int) -> list[str]:
    return _recent[chat_id]


def register_poll(poll_id: str, chat_id: int, correct: int) -> None:
    _polls[poll_id] = {"chat": chat_id, "correct": correct, "answered": set()}
    if len(_polls) > MAX_TRACKED:
        for key in list(_polls)[: MAX_TRACKED // 2]:
            _polls.pop(key, None)


def record_answer(poll_id: str, user_id: int, name: str, option_ids: list[int]) -> bool | None:
    """True/False for a counted answer, None when the poll is unknown or the user already answered."""
    poll = _polls.get(poll_id)
    if not poll or user_id in poll["answered"] or not option_ids:
        return None
    poll["answered"].add(user_id)
    _names[(poll["chat"], user_id)] = name[:32]
    right = option_ids[0] == poll["correct"]
    _scores[poll["chat"]][user_id] += 1 if right else 0
    return right


def leaderboard(chat_id: int, limit: int = 10) -> list[tuple[str, int]]:
    return [(_names.get((chat_id, uid), "игрок"), pts) for uid, pts in _scores[chat_id].most_common(limit) if pts > 0]
