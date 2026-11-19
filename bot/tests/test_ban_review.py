import asyncio
import os
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from handlers import ban_review as handler  # noqa: E402
from services import ban_review  # noqa: E402

OK = SimpleNamespace(error=None, data={"success": True})
ROW = {"tg_id": 555, "nickname": "<Steve>", "reason": "grief"}


def make_call(data, username="adm"):
    message = SimpleNamespace(html_text="card", edit_text=mock.AsyncMock())
    bot = SimpleNamespace(
        unban_chat_member=mock.AsyncMock(),
        create_chat_invite_link=mock.AsyncMock(return_value=SimpleNamespace(invite_link="https://t.me/+abc")),
        send_message=mock.AsyncMock(),
    )
    return SimpleNamespace(data=data, from_user=SimpleNamespace(id=1, username=username, full_name="Admin"),
                           message=message, bot=bot, answer=mock.AsyncMock())


class CardTests(unittest.TestCase):
    def test_card_escapes_html_and_buttons_carry_the_player(self):
        self.assertIn("&lt;Steve&gt;", ban_review.card_text(ROW))
        buttons = ban_review.keyboard(555).inline_keyboard[0]
        self.assertEqual([b.callback_data for b in buttons], ["banrev:ok:555", "banrev:keep:555"])

    def test_parse_callback_rejects_garbage(self):
        self.assertEqual(ban_review.parse_callback("banrev:ok:42"), ("ok", 42))
        for bad in ("", "banrev:nope:1", "banrev:ok:x", "other:ok:1", "banrev:ok"):
            self.assertIsNone(ban_review.parse_callback(bad))


class DecisionTests(unittest.TestCase):
    def test_confirm_lifts_ban_unbans_in_chat_and_invites(self):
        call = make_call("banrev:ok:555")
        with mock.patch.object(handler, "bot_lift_punishment", mock.AsyncMock(return_value=OK)) as lift, \
                mock.patch.object(ban_review, "bot_get_community_chat_id", mock.AsyncMock(return_value=SimpleNamespace(error=None, data=-100777))):
            asyncio.run(handler.on_decision(call))
        self.assertEqual(lift.await_args.args, (555, "BAN", 1))
        call.bot.unban_chat_member.assert_awaited_once_with(-100777, 555, only_if_banned=True)
        sent_to, text = call.bot.send_message.await_args.args[:2]
        self.assertEqual(sent_to, 555)
        self.assertIn("https://t.me/+abc", text)
        self.assertIn("подтвердил", call.message.edit_text.await_args.args[0])

    def test_keep_does_not_lift_or_invite(self):
        call = make_call("banrev:keep:555")
        with mock.patch.object(handler, "bot_ban_review_keep", mock.AsyncMock(return_value=OK)) as keep, \
                mock.patch.object(handler, "bot_lift_punishment", mock.AsyncMock()) as lift:
            asyncio.run(handler.on_decision(call))
        keep.assert_awaited_once_with(555, 1)
        lift.assert_not_awaited()
        call.bot.send_message.assert_not_awaited()

    def test_rpc_error_is_shown_and_nothing_else_happens(self):
        call = make_call("banrev:ok:555")
        failed = SimpleNamespace(error="ADMIN_LACKS_PERMISSION", data=None)
        with mock.patch.object(handler, "bot_lift_punishment", mock.AsyncMock(return_value=failed)):
            asyncio.run(handler.on_decision(call))
        call.bot.unban_chat_member.assert_not_awaited()
        call.bot.send_message.assert_not_awaited()
        self.assertTrue(call.answer.await_args.kwargs.get("show_alert"))

    def test_invite_failure_still_messages_the_player(self):
        bot = SimpleNamespace(unban_chat_member=mock.AsyncMock(), send_message=mock.AsyncMock(),
                              create_chat_invite_link=mock.AsyncMock(side_effect=RuntimeError("no rights")))
        with mock.patch.object(ban_review, "bot_get_community_chat_id", mock.AsyncMock(return_value=SimpleNamespace(error=None, data=-100777))):
            status = asyncio.run(ban_review.invite_back(bot, 555))
        self.assertIn("ссылку создать не удалось", status)
        bot.send_message.assert_awaited_once()


class NotifyTests(unittest.TestCase):
    def test_sends_one_card_per_player_to_admin_group(self):
        bot = SimpleNamespace(send_message=mock.AsyncMock())
        with mock.patch.object(ban_review.config, "ADMIN_GROUP_ID", -100999):
            sent = asyncio.run(ban_review.notify_admins(bot, [ROW, {"tg_id": 556, "nickname": "A"}]))
        self.assertEqual(sent, 2)
        self.assertEqual(bot.send_message.await_args_list[0].args[0], -100999)

    def test_no_admin_chat_means_nothing_is_sent(self):
        bot = SimpleNamespace(send_message=mock.AsyncMock())
        with mock.patch.object(ban_review.config, "ADMIN_GROUP_ID", None), mock.patch.object(ban_review.config, "OWNER_TG_ID", None):
            self.assertEqual(asyncio.run(ban_review.notify_admins(bot, [ROW])), 0)


if __name__ == "__main__":
    unittest.main()
