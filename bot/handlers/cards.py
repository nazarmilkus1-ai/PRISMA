import re
from html import escape

from aiogram import F, Router, types

from db.rpc import bot_market_reputation
from services.market_risk import stars
from utils.permissions import is_approved

router = Router(name="cards")
_UUID = re.compile(r"^[0-9a-fA-F\-]{32,36}$")


@router.callback_query(F.data.startswith("cd:"))
async def card_action(callback: types.CallbackQuery):
    parts = (callback.data or "").split(":", 2)
    if len(parts) != 3 or not callback.message:
        await callback.answer("Кнопка устарела.", show_alert=True)
        return
    action, arg = parts[1], parts[2]
    uid = callback.from_user.id

    if action == "rep":
        result = await bot_market_reputation(arg[:32])
        data = result.data if not result.error and isinstance(result.data, dict) else None
        if not data:
            await callback.answer("Игрок не найден.", show_alert=True)
            return
        await callback.answer()
        lines = [f"⭐ <b>{escape(str(data.get('nickname')))}</b>: {escape(stars(data.get('average'), int(data.get('reviews') or 0)))}"]
        lines += [f"• {r.get('rating')}/5 — {escape(str(r.get('comment') or 'без комментария'))}" for r in (data.get("recent") or [])]
        await callback.message.answer("\n".join(lines), parse_mode="HTML")
        return

    if not await is_approved(uid):
        await callback.answer("Это доступно участникам сервера.", show_alert=True)
        return
    if action == "off" and _UUID.match(arg):
        await callback.answer()
        await callback.message.answer(
            "💬 Предложите цену продавцу (отправьте в личке с ботом):\n"
            f"<code>/рынок предложить {escape(arg)} | ваша цена | заметка</code>", parse_mode="HTML")
        return
    if action == "evr" and _UUID.match(arg):
        from services.ai import member_tools
        ctx = member_tools.Context(uid, True, True)
        await member_tools.execute("propose_event_registration", {"event_id": arg}, ctx)
        await callback.answer()
        for text, markup in ctx.cards:
            await callback.message.answer(text, parse_mode="HTML", reply_markup=markup)
        return
    await callback.answer("Кнопка устарела.", show_alert=True)
