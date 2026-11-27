import pytest
from aiogram import types

from bot.services.community_membership import (
    _is_active_member,
    _is_admin,
    _is_missing_member_error,
    _text_only_permissions,
    _full_member_permissions,
)


@pytest.mark.parametrize(
    "status, expected",
    [
        ("member", True),
        ("administrator", True),
        ("creator", True),
        ("restricted", True),
        ("left", False),
        ("", False),
    ],
)
def test_is_active_member(status, expected):
    class Member:
        def __init__(self, status):
            self.status = status
            self.is_member = status != "left"

    member = Member(status)
    assert _is_active_member(member) == expected


def test_is_admin():
    class Member:
        def __init__(self, status):
            self.status = status

    admin = Member("administrator")
    creator = Member("creator")
    regular = Member("member")
    assert _is_admin(admin) is True
    assert _is_admin(creator) is True
    assert _is_admin(regular) is False


def test_is_missing_member_error():
    class ExceptionWithMessage:
        def __str__(self):
            return "user not found"

    exc = ExceptionWithMessage()
    assert _is_missing_member_error(exc) is True

    exc = Exception()
    assert _is_missing_member_error(exc) is False


def test_text_only_permissions():
    perm = _text_only_permissions()
    assert perm.can_send_messages is True
    assert perm.can_send_audios is False
    assert perm.can_send_documents is False
    assert perm.can_send_photos is False
    assert perm.can_send_videos is False
    assert perm.can_send_video_notes is False
    assert perm.can_send_voice_notes is False
    assert perm.can_send_polls is False
    assert perm.can_send_other_messages is False
    assert perm.can_add_web_page_previews is False


def test_full_member_permissions():
    perm = _full_member_permissions()
    assert perm.can_send_messages is True
    assert perm.can_send_audios is True
    assert perm.can_send_documents is True
    assert perm.can_send_photos is True
    assert perm.can_send_videos is True
    assert perm.can_send_video_notes is True
    assert perm.can_send_voice_notes is True
    assert perm.can_send_polls is True
    assert perm.can_send_other_messages is True
    assert perm.can_add_web_page_previews is True
