"""Weekly activity check → a warning (30 days, 5 active warnings = ban) for:
 * fewer than MIN_MINUTES in Minecraft during the last 7 days;
 * fewer than TG_MIN_MESSAGES messages in the community Telegram chat during the last 7 days
   (zero messages in 7 days is the same case: one warning, never two for one week of Telegram).

The database only selects candidates (read-only RPC); this worker applies the safeguards and issues the
WARN through the normal punishment RPC, so history, expiry and the 5-warning auto-ban stay in one place.

Safeguards (a bad week of data must never mass-punish people):
 * OFF unless ACTIVITY_WARN=1 (turn it on when the server is live);
 * skipped when the server clearly was not in normal use (fewer than MIN_ACTIVE_PLAYERS different players
   joined during the window) — plugin down, server closed, test period;
 * more than MAX_AUTO candidates → only a report to the admins, nothing is applied;
 * people with ACTIVE_WARNS_LIMIT or more active warnings are left to the staff (the 5th warning bans);
 * staff, newcomers (< 7 days), banned and already-warned-this-week players are excluded in SQL;
 * a reminder is sent the Saturday before, so nobody is surprised.
"""
from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from aiogram import Bot

import config
from db.rpc import bot_create_punishment, call_rpc_async

logger = logging.getLogger(__name__)

TZ = ZoneInfo(os.getenv("ACTIVITY_TZ", "Europe/Kyiv"))
MIN_MINUTES = int(os.getenv("ACTIVITY_MIN_MINUTES", "60"))
TG_MIN_MESSAGES = int(os.getenv("ACTIVITY_TG_MIN_MESSAGES", "50"))
WARN_HOUR = int(os.getenv("ACTIVITY_WARN_HOUR", "10"))
WARN_WEEKDAY = 0      # Monday
REMIND_WEEKDAY = 5    # Saturday
MIN_ACTIVE_PLAYERS = 5
MAX_AUTO = 30
ACTIVE_WARNS_LIMIT = 3
REASON = "Меньше {m} минут игры на сервере за неделю (автоматическая проверка активности)"
TG_REASON = "Меньше {m} сообщений в чате Telegram за неделю (автоматическая проверка активности)"
MC_SOURCE = "AUTO_INACTIVITY"
TG_SOURCE = "AUTO_TG_INACTIVITY"


def enabled() -> bool:
    return os.getenv("ACTIVITY_WARN", "0").strip().lower() in {"1", "true", "yes", "on"}


async def fetch(days: int = 7, minutes: int = MIN_MINUTES) -> dict | None:
    result = await call_rpc_async("bot_weekly_inactivity_candidates", {"p_days": days, "p_min_minutes": minutes})
    if result.error or not isinstance(result.data, dict):
        logger.warning("inactivity candidates unavailable: %s", result.error)
        return None
    return result.data


async def fetch_telegram(days: int = 7, messages: int = TG_MIN_MESSAGES) -> dict | None:
    result = await call_rpc_async("bot_weekly_telegram_inactivity_candidates", {"p_days": days, "p_min_messages": messages})
    if result.error or not isinstance(result.data, dict):
        logger.warning("telegram inactivity candidates unavailable: %s", result.error)
        return None
    return result.data


def plan(report: dict) -> dict:
    """Pure decision: what to do with a candidates report. Returns {action, warn, review, reason}."""
    candidates = [c for c in report.get("candidates") or [] if isinstance(c, dict) and c.get("tg_id")]
    if int(report.get("players") or 0) < MIN_ACTIVE_PLAYERS:
        return {"action": "skip", "warn": [], "review": [], "reason": "мало игроков заходило на сервер за неделю — данные ненадёжны"}
    if len(candidates) > MAX_AUTO:
        return {"action": "report", "warn": [], "review": candidates, "reason": f"кандидатов больше {MAX_AUTO} — применять автоматически небезопасно"}
    warn = [c for c in candidates if int(c.get("active_warns") or 0) < ACTIVE_WARNS_LIMIT]
    review = [c for c in candidates if c not in warn]
    return {"action": "apply", "warn": warn, "review": review, "reason": ""}


def _names(rows: list[dict], limit: int = 25) -> str:
    def one(r: dict) -> str:
        who = r.get("nickname") or r.get("tg_id")
        if "messages" in r:
            return f"{who} ({int(r.get('messages') or 0)} сообщ.)"
        return f"{who} ({int(r.get('minutes') or 0)} мин)"
    return ", ".join(one(r) for r in rows[:limit])


async def _section(report: dict, *, label: str, threshold: str, reason: str, source: str, apply: bool) -> list[str]:
    """One check (Minecraft or Telegram): decide, issue warnings through the punishment RPC, describe."""
    decision = plan(report)
    if decision["action"] != "apply":
        lines = [f"{label}Предупреждения НЕ выданы: {decision['reason']}."]
        if decision["review"]:
            lines.append("Кому не хватило активности: " + _names(decision["review"]))
        return lines
    issued = 0
    for row in decision["warn"] if apply else []:
        if not config.OWNER_TG_ID:
            break
        result = await bot_create_punishment(int(row["tg_id"]), "WARN", reason, config.OWNER_TG_ID, None, source, None)
        if not result.error:
            issued += 1
        else:
            logger.warning("inactivity warn failed for %s: %s", row.get("tg_id"), result.error)
    lines = [f"{label}Порог: {threshold} за 7 дней. Предупреждений выдано: <b>{issued}</b> из {len(decision['warn'])}."]
    if decision["warn"]:
        lines.append("Получили: " + _names(decision["warn"]))
    if decision["review"]:
        lines.append(f"Оставил вам (уже {ACTIVE_WARNS_LIMIT}+ активных предупреждений): " + _names(decision["review"]))
    return lines


async def run_check(bot: Bot, *, apply: bool = True) -> str:
    """One weekly pass (Minecraft + Telegram). Returns the admin summary text."""
    mc = await fetch()
    tg = await fetch_telegram()
    if mc is None and tg is None:
        return "⚠️ Проверка активности: данные недоступны (миграция bot_weekly_inactivity_candidates не применена?)."
    lines = ["🕒 <b>Проверка активности за неделю</b>"]
    if mc is not None:
        lines += await _section(mc, label="🎮 Minecraft: ", threshold=f"{MIN_MINUTES} мин", reason=REASON.format(m=MIN_MINUTES), source=MC_SOURCE, apply=apply)
    else:
        lines.append("🎮 Minecraft: данные недоступны.")
    if tg is not None:
        lines += await _section(tg, label="💬 Telegram: ", threshold=f"{TG_MIN_MESSAGES} сообщений", reason=TG_REASON.format(m=TG_MIN_MESSAGES), source=TG_SOURCE, apply=apply)
    else:
        lines.append("💬 Telegram: данные недоступны.")
    return "\n".join(lines)


async def _remind(bot: Bot, report: dict | None, text_for) -> int:
    if report is None:
        return 0
    decision = plan(report)
    if decision["action"] != "apply":
        return 0
    sent = 0
    for row in decision["warn"]:
        try:
            await bot.send_message(int(row["tg_id"]), text_for(row))
            sent += 1
        except Exception:
            continue
    return sent


async def send_reminders(bot: Bot) -> int:
    """Saturday: a friendly nudge to those who would get a warning on Monday."""
    sent = await _remind(
        bot, await fetch(),
        lambda r: f"⏳ За последние 7 дней вы наиграли {int(r.get('minutes') or 0)} мин из {MIN_MINUTES}. "
                  f"Зайдите на сервер до понедельника, иначе придёт предупреждение. Если не можете играть — напишите в поддержку.")
    sent += await _remind(
        bot, await fetch_telegram(),
        lambda r: f"⏳ За последние 7 дней вы написали {int(r.get('messages') or 0)} сообщений в чате из {TG_MIN_MESSAGES}. "
                  f"Загляните в чат до понедельника, иначе придёт предупреждение. Если не можете — напишите в поддержку.")
    return sent


async def run_inactivity_worker(bot: Bot, stop_event: asyncio.Event):
    if not enabled():
        logger.info("Activity warnings disabled (set ACTIVITY_WARN=1 when the server is live)")
        return
    now = datetime.now(TZ)
    done: set[tuple[str, str]] = set()
    # A restart after the hour must not repeat today's pass.
    if now.hour >= WARN_HOUR:
        done.add((now.date().isoformat(), "warn" if now.weekday() == WARN_WEEKDAY else "remind"))
    while not stop_event.is_set():
        now = datetime.now(TZ)
        today = now.date().isoformat()
        if now.hour >= WARN_HOUR:
            kind = "warn" if now.weekday() == WARN_WEEKDAY else "remind" if now.weekday() == REMIND_WEEKDAY else None
            if kind and (today, kind) not in done:
                done.add((today, kind))  # first: a failure must not become a retry storm
                try:
                    if kind == "warn":
                        text = await run_check(bot)
                        if config.ADMIN_GROUP_ID:
                            await bot.send_message(config.ADMIN_GROUP_ID, text, parse_mode="HTML", disable_notification=True)
                    else:
                        await send_reminders(bot)
                except Exception:
                    logger.exception("Inactivity pass failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=900)
        except asyncio.TimeoutError:
            pass
