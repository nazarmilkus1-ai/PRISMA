from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command

from db.rpc import bot_get_news

router = Router()


def _render_news(items: list[dict]) -> str:
    if not items:
        return "📰 <b>Новости PRISMA</b>\n\nПока опубликованных новостей нет."

    chunks = ["📰 <b>Новости PRISMA</b>"]
    for item in items[:5]:
        title = escape(str(item.get("title") or "Без заголовка"))
        body = escape(str(item.get("body") or "")).strip()
        kind = str(item.get("kind") or "NEWS")
        prefix = "Обновление" if kind == "UPDATE" else "Новость"
        if len(body) > 900:
            body = body[:897].rstrip() + "..."
        chunks.append(f"\n<b>{prefix}: {title}</b>\n{body}")
    return "\n".join(chunks)


async def send_news(message: types.Message):
    result = await bot_get_news(message.from_user.id)
    if result.error:
        await message.answer("❌ Не удалось загрузить новости. Попробуйте ещё раз позже.")
        return

    items = result.data if isinstance(result.data, list) else []
    await message.answer(_render_news(items), parse_mode="HTML")


@router.message(Command("news"))
async def cmd_news(message: types.Message):
    await send_news(message)


@router.callback_query(F.data == "news")
async def callback_news(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message is not None:
        await send_news(callback.message)
