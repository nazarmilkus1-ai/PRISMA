"""Deterministic filters for player lists, so common admin requests never need a model.

Bedrock players join through Floodgate, which prefixes their Minecraft nickname with "."
(the participants RPC has no platform column, so the prefix is the source of truth).
"""
from __future__ import annotations

import re
from dataclasses import dataclass

_BEDROCK = re.compile(r"бедрок|бэдрок|бедрок|bedrock|floodgate|mcpe", re.I)
_JAVA = re.compile(r"\bjava\b|джав|жав", re.I)
_NO_TG = re.compile(r"без\s+(юз|username|юзернейм|телеграм|telegram|тг)", re.I)
_WITH_TG = re.compile(r"(?<!без )(с|со)\s+(юз|username|юзернейм)", re.I)
_NICK = re.compile(r"\bник", re.I)
_WANTS_OTHER_COLUMNS = re.compile(r"юз|username|имя|имен|telegram|телеграм|\bтг\b|все данные", re.I)
# Qualifiers this module cannot apply: such requests must go to the model, not dump everyone.
_UNSUPPORTED = re.compile(
    r"онлайн|клан|уровн|рейтинг|\bтоп\b|забан|\bбан|мут|варн|предупр|ранг|давно|нов(ые|ых|ички)|вступил|регистр",
    re.I,
)

BEDROCK_PREFIX = "."


@dataclass(frozen=True)
class PlayerFilter:
    platform: str | None = None  # "bedrock" | "java" | None
    telegram: str | None = None  # "with" | "without" | None
    nicks_only: bool = False
    unsupported: bool = False

    @property
    def is_filtered(self) -> bool:
        return self.platform is not None or self.telegram is not None

    def describe(self) -> str:
        parts = []
        if self.platform == "bedrock":
            parts.append("Bedrock (ник с префиксом «.»)")
        elif self.platform == "java":
            parts.append("Java")
        if self.telegram == "without":
            parts.append("без Telegram-юзернейма")
        elif self.telegram == "with":
            parts.append("с Telegram-юзернеймом")
        return ", ".join(parts)


def parse_player_filter(text: str) -> PlayerFilter:
    text = text or ""
    platform = None
    if _BEDROCK.search(text) and not _JAVA.search(text):
        platform = "bedrock"
    elif _JAVA.search(text) and not _BEDROCK.search(text):
        platform = "java"
    telegram = None
    if _NO_TG.search(text):
        telegram = "without"
    elif _WITH_TG.search(text):
        telegram = "with"
    nicks_only = bool(_NICK.search(text)) and not _WANTS_OTHER_COLUMNS.search(text)
    return PlayerFilter(platform, telegram, nicks_only, bool(_UNSUPPORTED.search(text)))


def is_bedrock_nick(nickname: object) -> bool:
    return str(nickname or "").startswith(BEDROCK_PREFIX)


def apply_player_filter(rows: list, flt: PlayerFilter) -> list[dict]:
    result: list[dict] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        nickname = str(row.get("nickname") or "").strip()
        if flt.platform == "bedrock" and not is_bedrock_nick(nickname):
            continue
        if flt.platform == "java" and (not nickname or is_bedrock_nick(nickname)):
            continue
        has_username = bool(str(row.get("username") or "").strip())
        if flt.telegram == "without" and has_username:
            continue
        if flt.telegram == "with" and not has_username:
            continue
        result.append(row)
    return result
