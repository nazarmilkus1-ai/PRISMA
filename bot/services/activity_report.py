"""Who is silent in the community chat, who applied and who did not — one report, computed in the database.

Categories (see bot_activity_report): staff are listed apart; members = approved applicants; guests = in the
community but without an approved application (they never applied, or are still pending).
"""
from __future__ import annotations

from html import escape

from db.rpc import bot_activity_report, bot_get_community_chat_id

_ORDER = (
    ("member_silent", "✖️ Участники (одобрены), молчат дольше {days} дн."),
    ("member_never_wrote", "💤 Участники (одобрены), ни разу не писали в чате"),
    ("guest_silent", "⚠️ Без заявки, молчат дольше {days} дн."),
    ("guest_never_wrote", "👻 Без заявки, ни разу не писали"),
)


def _who(row: dict) -> str:
    user = f"@{row['username']}" if row.get("username") else str(row.get("tg_id"))
    name = str(row.get("name") or "").strip()
    return f"{user} — {name}" if name and name != user and name != str(row.get("tg_id")) else user


def render(rows: list[dict], days: int) -> str:
    groups: dict[str, list[dict]] = {}
    for row in rows:
        groups.setdefault(str(row.get("category")), []).append(row)
    count = lambda key: len(groups.get(key, []))  # noqa: E731
    lines = [f"📊 <b>Активность за {days} дн.</b> (по сообщениям в чате сообщества)", ""]
    total_members = sum(count(k) for k in ("member_silent", "member_never_wrote", "member_active"))
    total_guests = sum(count(k) for k in ("guest_silent", "guest_never_wrote", "guest_active"))
    lines.append(f"Участников (одобрены): <b>{total_members}</b> · без одобренной заявки: <b>{total_guests}</b> · персонал: <b>{count('staff')}</b>")
    lines.append(f"Подали заявку и неактивны: <b>{count('member_silent') + count('member_never_wrote')}</b> · "
                 f"не подали и неактивны: <b>{count('guest_silent') + count('guest_never_wrote')}</b>")
    for key, title in _ORDER:
        items = groups.get(key, [])
        if not items:
            continue
        lines += ["", f"<b>{title.format(days=days)} — {len(items)}</b>"]
        for index, row in enumerate(items, 1):
            silent = row.get("days_silent")
            tail = f" ({int(float(silent))} дн.)" if silent is not None else ""
            lines.append(f"{index}. {escape(_who(row))}{tail}")
    staff = groups.get("staff", [])
    if staff:
        lines += ["", "<i>Персонал в списки неактивных не входит.</i>"]
    return "\n".join(lines)


async def fetch(days: int = 7) -> tuple[list[dict] | None, int]:
    days = max(1, min(60, int(days)))
    chat = await bot_get_community_chat_id()
    chat_id = int(chat.data) if not chat.error and chat.data else 0
    if not chat_id:
        return None, days
    result = await bot_activity_report(chat_id, days)
    if result.error or not isinstance(result.data, list):
        return None, days
    return result.data, days


async def build(days: int = 7) -> str:
    rows, days = await fetch(days)
    if rows is None:
        return "❌ Не удалось получить отчёт об активности."
    return render(rows, days)
