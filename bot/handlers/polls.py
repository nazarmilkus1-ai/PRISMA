from aiogram import F, Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from db.rpc import bot_check_admin_permission, bot_create_poll, bot_finish_poll, bot_get_polls, bot_vote_poll, bot_rate_server
from fsm.states import PollForm
from keyboards.inline import poll_keyboard, rating_keyboard
from utils.permissions import DENIED_MESSAGE, is_approved, require_admin_mode
from utils.uuid_helpers import decode_uuid
from html import escape
from utils.errors import safe_rpc_error

router=Router()

@router.message(Command("rate"))
async def rate_server(message:types.Message):
    if not await is_approved(message.from_user.id): await message.answer(DENIED_MESSAGE); return
    await message.answer("⭐ Оцените сервер PRISMA от 1 до 5:", reply_markup=rating_keyboard())

@router.callback_query(F.data.startswith("server_rating:"))
async def rate_server_callback(callback:types.CallbackQuery):
    if not await is_approved(callback.from_user.id): await callback.answer("⏳ Доступно после одобрения заявки.",show_alert=True); return
    try: value=int(callback.data.split(":",1)[1])
    except Exception: await callback.answer("❌ Некорректная оценка.",show_alert=True); return
    result=await bot_rate_server(callback.from_user.id,value)
    if result.error or not (isinstance(result.data,dict) and result.data.get("success")):
        await callback.answer("❌ Не удалось сохранить оценку.",show_alert=True); return
    await callback.answer("✅ Оценка сохранена: "+str(value)+"★")

@router.callback_query(F.data == "player:rate")
async def rate_server_button(callback:types.CallbackQuery):
    await callback.answer()
    if callback.message: await rate_server(callback.message)

@router.message(Command("polls"))
async def cmd_polls(message:types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE); return
    r=await bot_get_polls(message.from_user.id)
    if r.error: await message.answer(f"❌ {safe_rpc_error(r)}",parse_mode="HTML"); return
    rows=r.data if isinstance(r.data,list) else []
    if not rows: await message.answer("🗳 Сейчас активных голосований нет."); return
    for poll in rows[:10]:
        text=f"🗳 <b>{escape(str(poll.get('question','')))}</b>"
        if poll.get('description'): text+=f"\n\n{escape(str(poll['description']))}"
        await message.answer(text,reply_markup=poll_keyboard(str(poll['id']),poll.get('options') or []),parse_mode="HTML")

@router.callback_query(F.data.startswith("v:"))
async def vote(callback:types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Доступно после одобрения заявки.",show_alert=True); return
    parts=callback.data.split(":")
    if len(parts)!=3: await callback.answer("❌ Некорректная кнопка.",show_alert=True); return
    try: poll_id=decode_uuid(parts[1]); option_id=decode_uuid(parts[2])
    except Exception: await callback.answer("❌ Некорректная кнопка.",show_alert=True); return
    r=await bot_vote_poll(poll_id,option_id,callback.from_user.id)
    if r.error or not (isinstance(r.data,dict) and r.data.get("success")):
        error = str(r.error or (r.data or {}).get("error") or "POLL_VOTE_FAILED")
        messages = {
            "USER_NOT_FOUND": "❌ Профиль не найден.",
            "USER_NOT_APPROVED": "⏳ Голосования доступны после одобрения заявки.",
            "POLL_NOT_ACTIVE": "⏳ Это голосование уже завершено.",
            "POLL_EXPIRED": "⏳ Срок голосования уже закончился.",
            "INVALID_OPTION": "❌ Этот вариант больше недоступен.",
            "CANNOT_CHANGE_VOTE": "⚠️ Вы уже голосовали в этом голосовании.",
            "MAX_CHOICES_REACHED": "⚠️ Вы уже выбрали максимальное число вариантов.",
        }
        await callback.answer(messages.get(error, "❌ Не удалось засчитать голос."), show_alert=True)
        return
    await callback.answer("✅ Голос засчитан!")

@router.message(Command("finish_poll"))
async def finish_poll(message:types.Message):
    if not await require_admin_mode(message):
        return
    p=await bot_check_admin_permission(message.from_user.id,"poll.finish")
    if p.error or not p.data: await message.answer("❌ Недостаточно прав."); return
    args=(message.text or "").split()
    if len(args)!=2: await message.answer("❌ Использование: /finish_poll <UUID>"); return
    r=await bot_finish_poll(args[1],message.from_user.id)
    await message.answer("✅ Голосование завершено." if isinstance(r.data,dict) and r.data.get("success") else f"❌ {safe_rpc_error(r, 'Не удалось завершить действие.')}",parse_mode="HTML")

@router.message(Command("poll_create"))
async def poll_create(message:types.Message,state:FSMContext):
    if not await require_admin_mode(message):
        return
    p=await bot_check_admin_permission(message.from_user.id,"poll.create")
    if p.error or not p.data: await message.answer("❌ Недостаточно прав."); return
    await state.set_state(PollForm.waiting_question); await message.answer("🗳 Введите вопрос голосования.")

@router.message(StateFilter(PollForm.waiting_question))
async def poll_question(message:types.Message,state:FSMContext):
    q=(message.text or "").strip()
    if not 3<=len(q)<=300: await message.answer("❌ Вопрос должен содержать 3–300 символов."); return
    await state.update_data(question=q); await state.set_state(PollForm.waiting_description); await message.answer("Введите описание или напишите <i>пропуск</i>.",parse_mode="HTML")

@router.message(StateFilter(PollForm.waiting_description))
async def poll_description(message:types.Message,state:FSMContext):
    d=(message.text or "").strip(); d=None if d.lower() in {"пропуск","-","—"} else d
    if d and len(d)>1000: await message.answer("❌ Максимум 1000 символов."); return
    await state.update_data(description=d); await state.set_state(PollForm.waiting_options); await message.answer("Введите варианты одним сообщением через `;` (2–11).",parse_mode="Markdown")

@router.message(StateFilter(PollForm.waiting_options))
async def poll_options(message:types.Message,state:FSMContext):
    options=[x.strip() for x in (message.text or "").split(";") if x.strip()]
    if not 2<=len(options)<=11: await message.answer("❌ Нужно от 2 до 11 вариантов."); return
    await state.update_data(options=options); await state.set_state(PollForm.waiting_chat); await message.answer("Введите Telegram chat ID, куда опубликовать голосование.")

@router.message(StateFilter(PollForm.waiting_chat))
async def poll_chat(message:types.Message,state:FSMContext):
    try: chat_id=int((message.text or "").strip())
    except ValueError: await message.answer("❌ Chat ID должен быть числом."); return
    d=await state.get_data(); r=await bot_create_poll(message.from_user.id,d['question'],d.get('description'),d['options'],chat_id)
    if r.error or not (isinstance(r.data,dict) and r.data.get('success')): await message.answer(f"❌ {safe_rpc_error(r, 'Не удалось создать голосование.')}",parse_mode="HTML"); return
    await state.clear(); await message.answer("✅ Голосование создано.")
