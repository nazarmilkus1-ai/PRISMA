"""/quiz — a quiz round (native Telegram quiz poll), /quiz_top — the chat leaderboard."""
import logging

from aiogram import F, Router, types
from aiogram.filters import Command, CommandObject

from services import quiz
from services.ai import ambient
from services.ai.client import is_configured

router = Router(name="quiz")
logger = logging.getLogger(__name__)

_GROUPS = F.chat.type.in_({"group", "supergroup", "private"})


@router.message(Command("quiz", "викторина"), _GROUPS)
async def quiz_command(message: types.Message, command: CommandObject):
    if not is_configured("user"):
        await message.reply("Викторина пока недоступна: PRISMA_AI не подключён.")
        return
    chat_id = message.chat.id
    why = quiz.allowed(chat_id)
    if why:
        await message.reply(why)
        return
    topic = "rules" if (command.args or "").strip().lower() in {"rules", "правила", "правило"} else "minecraft"
    try:
        await message.bot.send_chat_action(chat_id, "typing")
    except Exception:
        pass
    item = await quiz.generate(topic, ambient.adult(chat_id), quiz.recent(chat_id))
    if not item:
        await message.reply("Не получилось придумать вопрос, попробуйте ещё раз через минуту.")
        return
    quiz.remember_question(chat_id, item["question"])
    try:
        sent = await message.bot.send_poll(
            chat_id, item["question"], item["options"], type="quiz", is_anonymous=False,
            correct_option_id=item["correct"], explanation=item["explanation"], open_period=45)
    except Exception as exc:
        logger.warning("quiz poll failed: %s", exc)
        await message.reply("Telegram не принял вопрос, попробуйте ещё раз.")
        return
    quiz.register_poll(sent.poll.id, chat_id, item["correct"])


@router.poll_answer()
async def quiz_answer(answer: types.PollAnswer):
    if answer.user is None:
        return
    quiz.record_answer(answer.poll_id, answer.user.id, answer.user.first_name or "игрок", list(answer.option_ids or []))


@router.message(Command("quiz_top", "quiztop", "викторина_топ"), _GROUPS)
async def quiz_top(message: types.Message):
    board = quiz.leaderboard(message.chat.id)
    if not board:
        await message.reply("Очков пока нет. Начните: /quiz")
        return
    medals = ["🥇", "🥈", "🥉"]
    lines = ["🏆 Таблица викторины (сбрасывается при перезапуске бота):"]
    lines += [f"{medals[i] if i < 3 else f'{i + 1}.'} {name} — {pts}" for i, (name, pts) in enumerate(board)]
    await message.reply("\n".join(lines))
