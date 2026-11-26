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
    # Allow 2-4 options, correct index must be valid for the number of options
    if not isinstance(correct, int) or isinstance(correct, bool) or correct is None:
        return None
    if len(options) < 2 or len(options) > 4:
        return None
    if not 0 <= correct < len(options):
        return None
    if not 10 <= len(question) <= 300 or any(not 1 <= len(o) <= 100 for o in options) or len({o.casefold() for o in options}) != len(options):
        return None
    # Validate question contains actual content (not just ?)
    if question == "?" or not any(c.isalnum() for c in question):
        return None
    # Correct index must be valid for the actual number of options provided
    if correct >= len(options):
        return None
    return {"question": question, "options": options, "correct": correct,
            "explanation": str(data.get("explanation") or "").strip()[:190] or None}

def _system(topic: str, adult: int) -> str:
    """Generate system prompt for quiz AI based on topic and adult filter."""
    base = "Ты — полезный ассистент для Minecraft-сообщества. "
    if adult:
        base += "Отвечай с учетом возрастного ограничения. "
    base += f"Тема: {topic}. Формируй вопрос с 2-4 вариантами ответа, правильный индекс от 0 до 3."
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
            continue
        quiz = parse(str(message.get("content") or ""))
        if quiz:
            return quiz
    return None

_recent: dict[int, list[str]] = defaultdict(list)

def remember_question(chat_id: int, question: str) -> None:
    _recent[chat_id] = (_recent[chat_id] + [question[:80]])[-10:]

def recent(chat_id: int) -> list[str]:
    return _recent[chat_id]

def register_poll(poll_id: str, chat_id: int, correct: int, options: list[str] | None = None) -> None:
    if options is None:
        options = [f"option_{i}" for i in range(correct + 1)]  # default dummy options
    _polls[poll_id] = {"chat": chat_id, "correct": correct, "options": options, "answered": set()}
    if len(_polls) > MAX_TRACKED:
        for key in list(_polls)[: MAX_TRACKED // 2]:
            _polls.pop(key, None)

def record_answer(poll_id: str, user_id: int, name: str, option_ids: list[int]) -> bool | None:
    """True/False for a counted answer, None when the poll is unknown or the user already answered."""
    poll = _polls.get(poll_id)
    if not poll or not option_ids:
        return None
    # Validate option_id is within valid range for this poll's options
    option_id = option_ids[0]
    options = poll.get("options") or []
    if not options:
        return None
    if not isinstance(poll["correct"], int) or option_id < 0 or option_id >= len(options):
        return None
    # Track that this user answered using (chat_id, user_id) key
    answer_key = (poll["chat"], user_id)
    if answer_key in poll.setdefault("answered", set()):
        return None  # User already answered this poll - ignore duplicate
    poll.setdefault("answered", set()).add(answer_key)
    _names[answer_key] = name[:32]
    right = option_id == poll["correct"]
    # Add user to scores if not already tracked
    if user_id not in _scores[poll["chat"]]:
        _scores[poll["chat"]][user_id] = 0
    # Always increment or set score based on correctness
    if right:
        _scores[poll["chat"]][user_id] += 1
    # Wrong answers don't remove user from scores - they stay tracked for leaderboard
    return right

def leaderboard(chat_id: int, limit: int = 10) -> list[tuple[str, int]]:
    # Include all users who answered, regardless of score
    items = [(_names.get((chat_id, uid), "игрок"), pts) for uid, pts in _scores[chat_id].items() if (chat_id, uid) in _names]
    if not items:
        return []
    # Sort by score descending, then by name for stable order
    items.sort(key=lambda x: (-x[1], x[0]))
    return items[:limit]