"""Live numbers for the staff panel home screen. Each count is only fetched when the staff
member holds the matching view permission; a failed lookup shows as unknown, never as zero."""
from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from html import escape

from db.admin import open_appeals, open_reports, pending_applications
from db.player import get_online_players, get_server_metrics
from db.rpc import bot_get_server_status, bot_list_support_requests


def _can(perms, key: str) -> bool:
    return "*" in perms or key in perms


async def _count(fetch, admin_id: int):
    rows, err = await fetch(admin_id)
    return None if err else len(rows)


async def _support(admin_id: int):
    result = await bot_list_support_requests(admin_id, "OPEN", 100)
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        return None
    return len(data.get("items") or [])


async def snapshot(admin_id: int, perms: list[str]) -> dict:
    perms = list(perms or [])
    tasks: dict[str, object] = {}
    if _can(perms, "application.view"):
        tasks["applications"] = _count(pending_applications, admin_id)
    if _can(perms, "report.view"):
        tasks["reports"] = _count(open_reports, admin_id)
    if _can(perms, "appeal.view"):
        tasks["appeals"] = _count(open_appeals, admin_id)
    if _can(perms, "player.view"):
        tasks["support"] = _support(admin_id)
    tasks["status"] = bot_get_server_status()
    tasks["metrics"] = get_server_metrics()
    tasks["players"] = get_online_players()
    values = await asyncio.gather(*tasks.values(), return_exceptions=True)
    snap = {key: (None if isinstance(v, Exception) else v) for key, v in zip(tasks, values)}
    status = snap.pop("status", None)
    snap["server"] = status.data.get("status") if status is not None and not status.error and isinstance(status.data, dict) else None
    metrics = snap.pop("metrics", None)
    players = snap.pop("players", None)
    snap["max_players"] = (metrics[0] or {}).get("max_players") if metrics and not metrics[1] else None
    snap["online"] = len(players[0]) if players and not players[1] else None
    return snap


def render_home(role: str | None, perms: list[str], snap: dict) -> str:
    def num(key: str, label: str) -> str | None:
        if key not in snap:
            return None
        value = snap[key]
        return f"{label} <b>{'?' if value is None else value}</b>"

    queue = [x for x in (num("applications", "📋 заявки"), num("reports", "📢 репорты"),
                         num("appeals", "⚖️ апелляции"), num("support", "🆘 поддержка")) if x]
    online = snap.get("online")
    maximum = snap.get("max_players")
    lines = [
        "🛡 <b>PRISMA STAFF</b>" + (f" · {escape(str(role))}" if role else ""),
        "",
        "<b>Ждёт решения:</b> " + (" · ".join(queue) if queue else "нет доступных очередей"),
        f"<b>Сервер:</b> {escape(str(snap.get('server') or 'нет данных').upper())}"
        + (f" · онлайн <b>{online}{'/' + str(maximum) if maximum else ''}</b>" if online is not None else ""),
        "",
        f"<i>Обновлено {datetime.now(timezone.utc).strftime('%H:%M')} UTC</i>",
    ]
    return "\n".join(lines)
