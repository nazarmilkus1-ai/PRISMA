"""Market anti-fraud signals. Pure scoring: the data comes from bot_market_risk_data.

It never blocks or deletes anything: it only ranks recent listings so staff look at the risky
ones first. Every point has a reason that is shown to the reviewer.
"""
from __future__ import annotations

import re
from collections import Counter
from datetime import datetime, timezone

LOOK = 3     # worth a look
HIGH = 5     # look first

_LINK = re.compile(r"(https?://|www\.|t\.me/|discord\.gg|@\w{4,}|\b\+?\d[\d\s\-()]{8,}\d\b)", re.I)
_PHRASES = re.compile(r"(предоплат|сначала\s+(переведи|оплат|кинь)|без\s+риска|гарантия\s*100|100\s*%\s*гарант|только\s+сегодня|срочно\s+переведи)", re.I)


def _parse(ts) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except ValueError:
        return None


def _norm(row: dict) -> str:
    text = f"{row.get('title') or ''} {row.get('description') or ''}"
    return re.sub(r"\W+", " ", text.lower()).strip()


def _caps(title: str) -> bool:
    letters = [c for c in title if c.isalpha()]
    return len(letters) >= 8 and sum(c.isupper() for c in letters) / len(letters) > 0.7


def score_listings(rows: list[dict], now: datetime | None = None) -> list[dict]:
    now = now or datetime.now(timezone.utc)
    texts = Counter(_norm(r) for r in rows if _norm(r))
    scored: list[dict] = []
    for row in rows:
        points = 0.0
        reasons: list[str] = []
        created = _parse(row.get("seller_created_at"))
        if created and (now - created).total_seconds() < 48 * 3600:
            points += 2
            reasons.append("аккаунт продавца младше 2 суток")
        flood = int(row.get("seller_listings_24h") or 0)
        if flood >= 5:
            points += 3
            reasons.append(f"{flood} объявлений за сутки")
        elif flood >= 3:
            points += 1
            reasons.append(f"{flood} объявления за сутки")
        body = " ".join(str(row.get(k) or "") for k in ("title", "description", "terms"))
        if _LINK.search(body):
            points += 2
            reasons.append("ссылка или контакт вне платформы")
        if _PHRASES.search(body):
            points += 2
            reasons.append("типичные фразы мошенников (предоплата, «без риска»…)")
        if texts[_norm(row)] >= 2 and _norm(row):
            points += 3
            reasons.append("одинаковый текст в нескольких объявлениях")
        if _caps(str(row.get("title") or "")):
            points += 1
            reasons.append("заголовок капсом")
        low, total, avg = int(row.get("seller_low_reviews") or 0), int(row.get("seller_reviews") or 0), row.get("seller_avg_rating")
        if low >= 2:
            points += 3
            reasons.append(f"{low} плохих отзыва о продавце")
        elif total >= 3 and avg is not None and float(avg) < 3:
            points += 2
            reasons.append(f"низкий рейтинг продавца ({avg})")
        if total >= 3 and avg is not None and float(avg) >= 4.5 and low == 0:
            points -= 2
            reasons.append(f"хорошая репутация ({avg} из 5, {total} отзывов)")
        if points >= LOOK:
            scored.append({"id": row.get("id"), "title": row.get("title"), "seller": row.get("seller_nickname"),
                           "price": row.get("price_text"), "score": points,
                           "level": "high" if points >= HIGH else "look", "reasons": reasons})
    return sorted(scored, key=lambda x: -x["score"])


def stars(avg, count: int) -> str:
    if not count or avg is None:
        return "нет отзывов"
    return f"{float(avg):.1f}/5 ({count})"
