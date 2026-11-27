from bot.services.reminders import parse

def test_invalid_reminder_format():
    assert parse("30m") is None
