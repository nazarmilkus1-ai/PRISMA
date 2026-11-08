from aiogram.fsm.state import State, StatesGroup

class ApplicationForm(StatesGroup):
    agreement = State()
    full_name = State()
    birth_date = State()
    minecraft_nick = State()
    platform = State()
    goal = State()
    about = State()
    discovery_source = State()
    preview = State()

class LinkForm(StatesGroup):
    waiting_for_nick = State()

class ReportForm(StatesGroup):
    waiting_target = State()
    waiting_reason = State()

class PollForm(StatesGroup):
    waiting_question = State()
    waiting_description = State()
    waiting_options = State()
    waiting_chat = State()
    waiting_duration = State()

class ClanForm(StatesGroup):
    waiting_name = State()

class AppealForm(StatesGroup):
    waiting_reason = State()

class SupportForm(StatesGroup):
    waiting_message = State()


class AskForm(StatesGroup):
    waiting = State()
    admin_waiting = State()
