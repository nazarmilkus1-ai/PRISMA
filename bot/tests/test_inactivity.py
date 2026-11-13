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

from services import inactivity  # noqa: E402


def cand(i, minutes=10, warns=0):
    return {"tg_id": 1000 + i, "nickname": f"p{i}", "minutes": minutes, "active_warns": warns}


class PlanTests(unittest.TestCase):
    def test_skips_when_server_had_no_real_activity(self):
        decision = inactivity.plan({"players": 1, "candidates": [cand(1), cand(2)]})
        self.assertEqual(decision["action"], "skip")
        self.assertEqual(decision["warn"], [])

    def test_too_many_candidates_is_report_only(self):
        decision = inactivity.plan({"players": 40, "candidates": [cand(i) for i in range(inactivity.MAX_AUTO + 1)]})
        self.assertEqual(decision["action"], "report")
        self.assertEqual(decision["warn"], [])

    def test_players_with_many_active_warns_are_left_to_staff(self):
        decision = inactivity.plan({"players": 10, "candidates": [cand(1), cand(2, warns=3), cand(3, warns=4)]})
        self.assertEqual([c["tg_id"] for c in decision["warn"]], [1001])
        self.assertEqual({c["tg_id"] for c in decision["review"]}, {1002, 1003})

    def test_disabled_by_default(self):
        with mock.patch.dict(os.environ, {"ACTIVITY_WARN": ""}):
            self.assertFalse(inactivity.enabled())
        with mock.patch.dict(os.environ, {"ACTIVITY_WARN": "1"}):
            self.assertTrue(inactivity.enabled())


class RunCheckTests(unittest.TestCase):
    def test_issues_warns_through_the_punishment_rpc(self):
        report = {"players": 10, "joins": 30, "candidates": [cand(1), cand(2)]}
        ok = SimpleNamespace(error=None, data={"success": True})
        with mock.patch.object(inactivity, "fetch", mock.AsyncMock(return_value=report)), \
                mock.patch.object(inactivity, "bot_create_punishment", mock.AsyncMock(return_value=ok)) as create, \
                mock.patch.object(inactivity.config, "OWNER_TG_ID", 7):
            text = asyncio.run(inactivity.run_check(SimpleNamespace()))
        self.assertEqual(create.await_count, 2)
        args = create.await_args_list[0].args
        self.assertEqual((args[0], args[1], args[3], args[5]), (1001, "WARN", 7, "AUTO_INACTIVITY"))
        self.assertIn("выдано: <b>2</b>", text)

    def test_preview_applies_nothing(self):
        report = {"players": 10, "candidates": [cand(1)]}
        with mock.patch.object(inactivity, "fetch", mock.AsyncMock(return_value=report)), \
                mock.patch.object(inactivity, "bot_create_punishment", mock.AsyncMock()) as create, \
                mock.patch.object(inactivity.config, "OWNER_TG_ID", 7):
            text = asyncio.run(inactivity.run_check(SimpleNamespace(), apply=False))
        create.assert_not_awaited()
        self.assertIn("выдано: <b>0</b>", text)

    def test_unavailable_data_reports_instead_of_crashing(self):
        with mock.patch.object(inactivity, "fetch", mock.AsyncMock(return_value=None)):
            self.assertIn("недоступны", asyncio.run(inactivity.run_check(SimpleNamespace())))

    def test_reminders_only_when_data_is_trustworthy(self):
        bot = SimpleNamespace(send_message=mock.AsyncMock())
        with mock.patch.object(inactivity, "fetch", mock.AsyncMock(return_value={"players": 1, "candidates": [cand(1)]})):
            self.assertEqual(asyncio.run(inactivity.send_reminders(bot)), 0)
        with mock.patch.object(inactivity, "fetch", mock.AsyncMock(return_value={"players": 9, "candidates": [cand(1), cand(2)]})):
            self.assertEqual(asyncio.run(inactivity.send_reminders(bot)), 2)
        self.assertEqual(bot.send_message.await_count, 2)


if __name__ == "__main__":
    unittest.main()
