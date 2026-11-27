from services import reminders  # noqa: E402


def test_parse_invalid_reminder_format():
    assert reminders.parse("30m") is None