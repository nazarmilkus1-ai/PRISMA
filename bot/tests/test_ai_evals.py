import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.ai import evals  # noqa: E402


class EvalTests(unittest.IsolatedAsyncioTestCase):
    def test_golden_cases_route_as_documented(self):
        self.assertEqual(evals.deterministic_failures(), [])

    def test_judge_catches_invented_facts(self):
        ip_case = next(c for c in evals.CASES if "айпи" in c.question)
        self.assertIsNotNone(evals.judge(ip_case, "Адрес: 192.168.1.5", ()))
        self.assertIsNotNone(evals.judge(ip_case, "Смотри play.fake-server.com", ()))
        self.assertIsNone(evals.judge(ip_case, "Адрес не знаю, смотри сайт prisma.example", ("prisma.example",)))
        self.assertEqual(evals.judge(ip_case, "", ()), "empty answer")

    def test_judge_requires_keywords(self):
        case = next(c for c in evals.CASES if c.question.startswith("как подать"))
        self.assertIsNotNone(evals.judge(case, "Не знаю", ()))
        self.assertIsNone(evals.judge(case, "Подайте заявку в боте", ()))

    async def test_run_live_counts_and_survives_errors(self):
        async def ask(question):
            if "правил" in question:
                raise RuntimeError("boom")
            return "заявку подайте в боте, правила, рынок, ивент, поддержка, вход, адрес неизвестен, цены неизвестны"

        passed, failures = await evals.run_live(ask)
        self.assertTrue(any("boom" in f for f in failures))
        self.assertGreater(passed, 0)


if __name__ == "__main__":
    unittest.main()
