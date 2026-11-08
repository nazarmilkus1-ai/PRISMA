from datetime import datetime, timedelta, timezone

from config import MODERATION_GROUP_ID

from aiogram import Router, types
from aiogram.filters import Command
from db.rpc import bot_check_admin_permission, bot_create_punishment, bot_find_user, bot_get_punishment_history, bot_lift_punishment
from utils.helpers import format_punishment, parse_duration, parse_command_args
from utils.permissions import require_admin_mode
from html import escape
from utils.chat_permissions import muted_chat_permissions, unmuted_chat_permissions
from services.community_membership import ensure_onboarding_restriction
from utils.errors import safe_rpc_error

router=Router()
PERMS={"warn":"punishment.warn","mute":"punishment.mute","ban":"punishment.ban","kick":"punishment.kick","unmute":"punishment.remove","unwarn":"punishment.remove","history":"punishment.view_history"}

def target_from(data):
    return data if isinstance(data,dict) else None

async def require_perm(message, key):
    if not await require_admin_mode(message):
        return False
    r=await bot_check_admin_permission(message.from_user.id,key)
    if r.error or not r.data:
        await message.answer("❌ Недостаточно прав или вы не администратор."); return False
    return True

async def resolve_target(identifier):
    r=await bot_find_user(identifier)
    if r.error: return None,r.error
    if isinstance(r.data,dict) and r.data.get("error"): return None,str(r.data["error"])
    return target_from(r.data),None

for cmd in ("warn","mute","ban","kick"):
    async def handler(message: types.Message, _cmd=cmd):
        if not await require_perm(message, PERMS[_cmd]): return
        args=parse_command_args(message.text or "")
        if len(args)<3:
            await message.answer(f"❌ Использование: /{_cmd} <ник/@username/ID> <причина> [10m]"); return
        target,err=await resolve_target(args[1])
        if not target: await message.answer("❌ Игрок не найден."); return
        reason=args[2]; duration=None
        if _cmd in {"mute","ban"} and len(args)>=4:
            try: duration=parse_duration(args[3])
            except ValueError as exc: await message.answer(f"❌ {exc}"); return
        if _cmd == "mute" and duration is None:
            duration = 2 * 60 * 60
        minutes = None if duration is None else max(1, (duration + 59) // 60)
        r=await bot_create_punishment(target.get("tg_id"),_cmd,reason,message.from_user.id,minutes,"manual",None)
        if r.error or not isinstance(r.data,dict) or not r.data.get("success"):
            await message.answer(f"❌ {safe_rpc_error(r, 'Не удалось выдать наказание.')}",parse_mode="HTML"); return

        tg_id = int(target.get("tg_id"))
        auto_banned = bool(r.data.get("auto_banned"))
        if MODERATION_GROUP_ID and (_cmd in {"mute", "ban"} or auto_banned):
            try:
                until = None
                if _cmd == "mute":
                    if bool(r.data.get("has_indefinite_mute")):
                        until = None
                    else:
                        effective_expiry = r.data.get("muted_until") or r.data.get("expires_at")
                        if effective_expiry:
                            until = datetime.fromisoformat(str(effective_expiry).replace("Z", "+00:00"))
                            if until.tzinfo is None:
                                until = until.replace(tzinfo=timezone.utc)
                        elif minutes is not None:
                            until = datetime.now(timezone.utc) + timedelta(minutes=minutes)
                    await message.bot.restrict_chat_member(
                        MODERATION_GROUP_ID,
                        tg_id,
                        permissions=muted_chat_permissions(),
                        until_date=until,
                        use_independent_chat_permissions=True,
                    )
                else:
                    if minutes is not None:
                        until = datetime.now(timezone.utc) + timedelta(minutes=minutes)
                    await message.bot.ban_chat_member(
                        MODERATION_GROUP_ID,
                        tg_id,
                        until_date=until if _cmd == "ban" else None,
                        revoke_messages=False,
                    )
            except Exception:
                await message.answer("⚠️ Наказание сохранено в PRISMA, но Telegram-группа не приняла ограничение.", parse_mode="HTML")
                return

        label = {"warn":"варн","mute":"мут","ban":"бан","kick":"кик"}.get(_cmd, _cmd)
        extra = " · 5 активных варнов → бан" if auto_banned else (f" на {minutes} мин." if minutes else "")
        await message.answer(
            f"✅ Наказание <b>{label}</b>{extra} выдано игроку <b>{escape(str(target.get('minecraft_nick') or target.get('username') or args[1]))}</b>.",
            parse_mode="HTML",
        )
    router.message.register(handler, Command(cmd))

@router.message(Command("unmute"))
async def cmd_unmute(message: types.Message):
    if not await require_perm(message,"punishment.remove"): return
    args=parse_command_args(message.text or "")
    if len(args)!=2: await message.answer("❌ Использование: /unmute <ник/@username/ID>"); return
    target,err=await resolve_target(args[1])
    if not target: await message.answer("❌ Игрок не найден."); return
    r=await bot_lift_punishment(target.get("tg_id"),"mute",message.from_user.id)
    if r.error or not isinstance(r.data, dict) or not r.data.get("success"):
        await message.answer(f"❌ {safe_rpc_error(r, 'Не удалось снять мут.')}", parse_mode="HTML")
        return

    data = r.data
    tg_id = int(target.get("tg_id"))
    if MODERATION_GROUP_ID:
        try:
            if bool(data.get("is_muted")):
                if bool(data.get("has_indefinite_mute")):
                    until = None
                else:
                    raw_expiry = data.get("muted_until")
                    if not raw_expiry:
                        raise ValueError("missing effective mute expiry")
                    until = datetime.fromisoformat(str(raw_expiry).replace("Z", "+00:00"))
                    if until.tzinfo is None:
                        until = until.replace(tzinfo=timezone.utc)
                await message.bot.restrict_chat_member(
                    MODERATION_GROUP_ID,
                    tg_id,
                    permissions=muted_chat_permissions(),
                    until_date=until,
                    use_independent_chat_permissions=True,
                )
            else:
                await message.bot.restrict_chat_member(
                    MODERATION_GROUP_ID,
                    tg_id,
                    permissions=unmuted_chat_permissions(),
                    use_independent_chat_permissions=True,
                )
        except Exception:
            await message.answer("⚠️ Мут обновлён в PRISMA, но Telegram-группу не удалось синхронизировать.", parse_mode="HTML")
            return

        if not bool(data.get("is_muted")):
            try:
                await ensure_onboarding_restriction(
                    message.bot,
                    tg_id,
                    str(target.get("full_name") or target.get("username") or tg_id),
                )
            except Exception:
                pass

    await message.answer("✅ Мут снят." if not data.get("is_muted") else "ℹ️ Один мут снят, но другое активное ограничение ещё действует.", parse_mode="HTML")

@router.message(Command("unban"))
async def cmd_unban(message: types.Message):
    if not await require_perm(message, "punishment.remove"):
        return
    args = parse_command_args(message.text or "")
    if len(args) != 2:
        await message.answer("❌ Использование: /unban <ник/@username/ID>")
        return
    target, err = await resolve_target(args[1])
    if not target:
        await message.answer("❌ Игрок не найден.")
        return
    result = await bot_lift_punishment(target.get("tg_id"), "ban", message.from_user.id)
    if result.error:
        await message.answer(f"❌ {safe_rpc_error(result)}", parse_mode="HTML")
        return
    await message.answer("✅ Бан снят.")

@router.message(Command("unwarn"))
async def cmd_unwarn(message: types.Message):
    if not await require_perm(message,"punishment.remove"): return
    args=parse_command_args(message.text or "")
    if len(args)!=2: await message.answer("❌ Использование: /unwarn <ник/@username/ID>"); return
    target,err=await resolve_target(args[1])
    if not target: await message.answer("❌ Игрок не найден."); return
    r=await bot_lift_punishment(target.get("tg_id"),"warn",message.from_user.id)
    await message.answer("✅ Предупреждение снято." if not r.error else f"❌ {safe_rpc_error(r, 'Не удалось снять предупреждение.')}",parse_mode="HTML")

@router.message(Command("history"))
async def cmd_history(message: types.Message):
    if not await require_perm(message,"punishment.view_history"): return
    args=parse_command_args(message.text or "")
    if len(args)!=2: await message.answer("❌ Использование: /history <ник/@username/ID>"); return
    target,err=await resolve_target(args[1])
    if not target: await message.answer("❌ Игрок не найден."); return
    r=await bot_get_punishment_history(target.get("tg_id"),message.from_user.id)
    if r.error or not isinstance(r.data,list): await message.answer(f"❌ {safe_rpc_error(r)}",parse_mode="HTML"); return
    if not r.data: await message.answer("📋 История наказаний пуста."); return
    await message.answer("📋 <b>История наказаний</b>\n\n"+"\n\n".join(format_punishment(x) for x in r.data[:20]),parse_mode="HTML")
