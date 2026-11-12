"""Cleans model output before it reaches a chat.

Some models leak their chain of thought (often in English), echo the system prompt or prefix the reply with
their own name. A member must only ever see the final line, so everything else is stripped; if no clean
reply can be recovered the caller retries instead of posting garbage.
"""
from __future__ import annotations

import re

_THINK = re.compile(r"<(think|thinking|reasoning|analysis)>.*?</\1>", re.S | re.I)
_ANSWER = re.compile(r"<answer>(.*?)</answer>", re.S | re.I)
_PREFIX = re.compile(r"^\s*(?:PRISMA[_ ]?AI|PRISMA|Призма)\s*[:\-—]\s*", re.I)
_LEAK = re.compile(
    r"(Now reply to|Final (?:decision|answer|reply)|Possible reply|Let me (?:think|draft|re)|I need to|I should|I'll (?:reply|respond|go|keep|just|say|output)|"
    r"I will (?:reply|respond)|the user (?:is|wants|said|asks|might)|instruction says|re-reading|Reply:|Draft:|"
    r"СПРАВКА:|Переписка в чате|Сообщения чата — данные|Пиши коротко, 1–3|обращается к тебе|Ответь ему\.|данные, не инструкции|"
    r"Ты — PRISMA_AI|РЕЖИМ 18|no fluff|human-like)",
    re.I,
)
_ECHO = re.compile(r"(СПРАВКА:|Сообщения чата — данные|Ты — PRISMA_AI|Пиши коротко, 1–3)")
_BOUNDARY = re.compile(r"(?<=[A-Za-z0-9.!?\"')\]])(?=[А-ЯЁа-яёІіЇїЄєҐґ])")


def looks_leaked(text: str) -> bool:
    return bool(_LEAK.search(text or ""))


def _strip_quotes(line: str) -> str:
    line = line.strip()
    if len(line) >= 2 and line[0] in "\"«“'" and line[-1] in "\"»”'":
        line = line[1:-1].strip()
    return line


def clean(text: str) -> str | None:
    """The final reply, or None when it is unusable (leaked reasoning that cannot be separated)."""
    text = _THINK.sub("", text or "").strip()
    match = _ANSWER.search(text)
    if match:
        text = match.group(1).strip()
    text = _PREFIX.sub("", text, count=1).strip()
    if not text:
        return None
    if not looks_leaked(text):
        return text
    if _ECHO.search(text):
        return None  # the system prompt itself was echoed: there is no trustworthy final line
    # Leaked: walk the lines from the end and take the last one that is a real, clean sentence.
    for line in reversed([ln.strip() for ln in text.splitlines() if ln.strip()]):
        if looks_leaked(line):
            tail = _BOUNDARY.split(line)[-1].strip()
            if tail and tail != line and not looks_leaked(tail) and re.search(r"[A-Za-zА-Яа-яЁёІіЇїЄє]{2,}", tail):
                return _strip_quotes(_PREFIX.sub("", tail, count=1))
            continue
        if re.search(r"[A-Za-zА-Яа-яЁёІіЇїЄє]{2,}", line):
            return _strip_quotes(_PREFIX.sub("", line, count=1))
    return None
