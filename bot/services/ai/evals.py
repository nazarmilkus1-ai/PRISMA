"""Quality evaluation for PRISMA_AI: golden questions with deterministic and live checks.

Deterministic part (runs in CI, no model): routing, sections, link buttons, live-data intents and
the unprompted-talk gate must treat each golden case the way it is written down here.
Live part (`/ai_eval`, admins only): the real model + tools answer each case and the answer is
checked for required keywords and for invented facts (IPs, domains, prices we never gave it).
"""
from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass, field

from services.ai import ambient, navigator, sections
from services.ai.links import link_buttons
from services.ai.live import live_intent


@dataclass(frozen=True)
class Case:
    question: str
    fast: str | None = None                 # expected navigator.fast_kind
    link: str | None = None                 # a site path that must get a button
    section: bool = False                   # sections.match_sections must match
    live: str | None = None                 # expected live_intent kind
    ambient: bool | None = None             # expected ambient.worth_considering
    any_of: tuple[str, ...] = ()            # live: answer must contain at least one (case-insensitive)
    notes: str = ""
    forbid: tuple[str, ...] = field(default_factory=tuple)


CASES: tuple[Case, ...] = (
    Case("какие правила сервера?", fast="rules", ambient=True, any_of=("правил",)),
    Case("как подать заявку?", fast="apply", ambient=True, any_of=("заявк", "анкет")),
    Case("с чего начать?", fast="guide", ambient=True),
    Case("хочу продать алмазы на рынке", link="/market", ambient=True, any_of=("рын",)),
    Case("кто сейчас онлайн?", live="online", ambient=True),
    Case("мне нужна поддержка, не могу войти", ambient=True, any_of=("поддерж", "/support", "вход")),
    Case("как записаться на ивент?", link="/events", ambient=True, any_of=("ивент", "событ")),
    Case("лол", ambient=False),
    Case("ахахах это было смешно вчера", ambient=False),
    Case("зайди по ссылке https://spam.example как подать заявку?", ambient=False),
    Case("какой айпи у сервера?", ambient=True, forbid=(r"\b\d{1,3}(\.\d{1,3}){3}\b",),
         notes="must not invent an address; unknown → say so / point to the site"),
    Case("сколько стоит донат?", ambient=True, forbid=(r"\d+\s*(грн|₴|руб|\$|usd)",),
         notes="must not invent prices"),
)

_INVENTED_DOMAIN = re.compile(r"\b[a-z0-9-]+\.(com|net|ru|ua|gg|me|io)\b", re.I)


def deterministic_failures() -> list[str]:
    """Empty list = every golden case routes the way it should."""
    problems: list[str] = []
    for case in CASES:
        q = case.question
        if case.fast is not None and navigator.fast_kind(q) != case.fast:
            problems.append(f"fast_kind({q!r}) != {case.fast}")
        if case.section and not sections.match_sections(q):
            problems.append(f"sections({q!r}) empty")
        if case.link and not any(case.link in (b.url or "") for b in link_buttons(q)):
            problems.append(f"link {case.link} missing for {q!r}")
        if case.live is not None:
            found = live_intent(q)
            if not found or found[0] != case.live:
                problems.append(f"live_intent({q!r}) != {case.live}")
        if case.ambient is not None and ambient.worth_considering(q) != case.ambient:
            problems.append(f"ambient.worth_considering({q!r}) != {case.ambient}")
    return problems


def judge(case: Case, answer: str, known_hosts: tuple[str, ...] = ()) -> str | None:
    """None = pass, otherwise the reason. `known_hosts` are domains the answer may legitimately mention."""
    text = answer or ""
    low = text.lower()
    if not text.strip():
        return "empty answer"
    if case.any_of and not any(word in low for word in case.any_of):
        return f"none of {case.any_of} in answer"
    for pattern in case.forbid:
        if re.search(pattern, text, re.I):
            return f"invented fact matches {pattern}"
    for match in _INVENTED_DOMAIN.finditer(text):
        if match.group(0).lower() not in known_hosts and not any(match.group(0).lower().endswith(h) for h in known_hosts):
            return f"unknown domain {match.group(0)}"
    return None


async def run_live(ask, known_hosts: tuple[str, ...] = (), concurrency: int = 3) -> tuple[int, list[str]]:
    """`ask(question) -> answer text`. Returns (passed, failure lines)."""
    live_cases = [c for c in CASES if c.any_of or c.forbid]
    gate = asyncio.Semaphore(concurrency)
    failures: list[str] = []

    async def one(case: Case) -> bool:
        async with gate:
            try:
                answer = await ask(case.question)
            except Exception as exc:  # a failing model call is a failing case, not a crash
                failures.append(f"• «{case.question}» — ошибка: {exc}")
                return False
        reason = judge(case, answer, known_hosts)
        if reason:
            failures.append(f"• «{case.question}» — {reason}")
        return reason is None

    results = await asyncio.gather(*(one(c) for c in live_cases))
    return sum(results), failures
