"""Convert the Markdown subset models like to emit into Telegram-safe HTML.

Everything is escaped first, then a small set of constructs is turned into the tags
Telegram supports. Model output therefore can never inject its own HTML.
"""
from __future__ import annotations

import re
from html import escape

_FENCE = re.compile(r"```[^\n`]*\n?(.*?)```", re.S)
_CODE = re.compile(r"`([^`\n]+)`")
_BOLD = re.compile(r"\*\*(.+?)\*\*|__(.+?)__", re.S)
_ITALIC = re.compile(r"(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])")
_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", re.M)
_BULLET = re.compile(r"^(\s*)[-*•]\s+", re.M)
_LINK = re.compile(r"\[([^\]\n]+)\]\((https?://[^\s)]+)\)")


def to_telegram_html(text: str) -> str:
    stash: list[str] = []

    def keep(html: str) -> str:
        stash.append(html)
        return f"\x00{len(stash) - 1}\x00"

    text = _FENCE.sub(lambda m: keep(f"<pre>{escape(m.group(1).strip(chr(10)))}</pre>"), text or "")
    text = _CODE.sub(lambda m: keep(f"<code>{escape(m.group(1))}</code>"), text)
    text = escape(text, quote=False)
    text = _LINK.sub(lambda m: keep(f'<a href="{escape(m.group(2), quote=True)}">{m.group(1)}</a>'), text)
    text = _HEADING.sub(lambda m: f"<b>{m.group(1)}</b>", text)
    text = _BOLD.sub(lambda m: f"<b>{m.group(1) or m.group(2)}</b>", text)
    text = _ITALIC.sub(lambda m: f"<i>{m.group(1)}</i>", text)
    text = _BULLET.sub(lambda m: f"{m.group(1)}• ", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: stash[int(m.group(1))], text)


def strip_markdown(text: str) -> str:
    """Plain-text fallback when Telegram rejects the HTML."""
    text = _FENCE.sub(lambda m: m.group(1), text or "")
    text = _CODE.sub(lambda m: m.group(1), text)
    text = _BOLD.sub(lambda m: m.group(1) or m.group(2), text)
    return _HEADING.sub(lambda m: m.group(1), text)
