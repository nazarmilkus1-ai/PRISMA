import re

from aiogram import F, Router, types

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

    if not await is_approved(uid):
        await callback.answer("Это доступно участникам сервера.", show_alert=True)
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
