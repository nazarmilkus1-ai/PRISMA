import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.ai import ambient  # noqa: E402


class AmbientTests(unittest.TestCase):
    def test_worth_considering(self):
        self.assertTrue(ambient.worth_considering("как подать заявку на сервер?"))
        self.assertTrue(ambient.worth_considering("хочу продать алмазы на рынке"))
        self.assertFalse(ambient.worth_considering("лол"))
        self.assertFalse(ambient.worth_considering("заходи https://spam.example как подать?"))
        self.assertFalse(ambient.worth_considering("/start что-то там сервер"))
        self.assertFalse(ambient.worth_considering("ахахах это было смешно вчера"))
        self.assertFalse(ambient.worth_considering("x" * 500 + "?"))

    def test_cooldowns_and_cap(self):
        now = 1_000_000.0
        self.assertTrue(ambient.can_speak(1, 10, now))
        ambient.mark_spoke(1, 10, now)
        self.assertFalse(ambient.can_speak(1, 11, now + 10))    # chat cooldown
        self.assertFalse(ambient.can_speak(1, 10, now + 120))   # user cooldown
        self.assertTrue(ambient.can_speak(1, 11, now + 120))
        self.assertTrue(ambient.can_speak(1, 10, now + 400))

    def test_daily_cap(self):
        base = 86400 * 100 + 100.0
        for i in range(ambient.CHAT_DAILY_CAP):
            ambient.mark_spoke(2, 100 + i, base + i)
        self.assertFalse(ambient.can_speak(2, 999, base + 200))
        self.assertTrue(ambient.can_speak(2, 999, base + 86400))  # next day

    def test_classify_budget(self):
        now = 9_000_000.0
        ok = [ambient.classify_budget(3, now + i) for i in range(ambient.CLASSIFY_PER_HOUR + 5)]
        self.assertEqual(sum(ok), ambient.CLASSIFY_PER_HOUR)
        self.assertTrue(ambient.classify_budget(3, now + 4000))

    def test_parse_decision_is_defensive(self):
        self.assertEqual(ambient.parse_decision('{"action":"invite","intent":"apply"}'), {"action": "invite", "intent": "apply"})
        self.assertEqual(ambient.parse_decision("мусор")["action"], "none")
        self.assertEqual(ambient.parse_decision('{"action":"ban everyone"}')["action"], "none")
        self.assertEqual(ambient.parse_decision('текст {"action":"answer","intent":"hack"} ещё')["intent"], "general")

    def test_answered_by_human(self):
        ambient._buffers.pop(7, None)
        ambient.observe(7, 1, 100, "A", "как зайти на сервер?")
        self.assertFalse(ambient.answered_by_human(7, 1, 100))
        ambient.observe(7, 2, 101, "B", "через лаунчер")
        self.assertTrue(ambient.answered_by_human(7, 1, 100))

    def test_invite_links_and_start_payload(self):
        self.assertEqual(ambient.invite_url("bot", "apply"), "https://t.me/bot?start=ai_apply")
        self.assertEqual(ambient.invite_url("bot", "../x"), "https://t.me/bot?start=ai_general")
        self.assertEqual(ambient.intent_from_start("ai_market")[0], "market")
        self.assertIsNone(ambient.intent_from_start("ai_hack"))
        self.assertIsNone(ambient.intent_from_start("abc123"))

    def test_invite_text_escapes_name(self):
        self.assertNotIn("<b>", ambient.invite_text("<b>x</b>", "apply"))


if __name__ == "__main__":
    unittest.main()
