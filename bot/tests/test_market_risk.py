import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import market_risk as mr  # noqa: E402

NOW = datetime(2026, 11, 12, 12, 0, tzinfo=timezone.utc)


def row(**kw):
    base = {"id": "1", "title": "Продам алмазы", "description": "64 шт", "seller_nickname": "A",
            "seller_created_at": (NOW - timedelta(days=30)).isoformat(), "seller_listings_24h": 1,
            "seller_reviews": 0, "seller_low_reviews": 0, "seller_avg_rating": None}
    base.update(kw)
    return base


class RiskTests(unittest.TestCase):
    def test_normal_listing_is_quiet(self):
        self.assertEqual(mr.score_listings([row()], NOW), [])

    def test_scam_pattern_is_flagged_with_reasons(self):
        bad = row(description="Нужна предоплата, пиши в t.me/scammer", seller_created_at=(NOW - timedelta(hours=3)).isoformat())
        result = mr.score_listings([bad], NOW)
        self.assertEqual(result[0]["level"], "high")
        self.assertGreaterEqual(len(result[0]["reasons"]), 3)

    def test_duplicates_and_flood(self):
        a = row(id="1", seller_listings_24h=6)
        b = row(id="2", seller_nickname="B", seller_listings_24h=6)
        result = mr.score_listings([a, b], NOW)
        self.assertEqual(len(result), 2)
        self.assertTrue(any("одинаков" in r for r in result[0]["reasons"]))

    def test_good_reputation_lowers_score(self):
        risky = dict(description="пиши https://x.example", seller_listings_24h=3)
        plain = mr.score_listings([row(**risky)], NOW)
        trusted = mr.score_listings([row(**risky, seller_reviews=5, seller_avg_rating=4.8)], NOW)
        self.assertTrue(plain)
        self.assertFalse(trusted)

    def test_bad_reviews_flag(self):
        result = mr.score_listings([row(seller_low_reviews=2, seller_reviews=3, seller_avg_rating=2.0)], NOW)
        self.assertTrue(result)

    def test_stars(self):
        self.assertEqual(mr.stars(None, 0), "нет отзывов")
        self.assertEqual(mr.stars(4.666, 3), "4.7/5 (3)")


class WiringTests(unittest.TestCase):
    def test_tools_registered(self):
        os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
        os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
        os.environ.setdefault("BOT_TOKEN", "123456:TEST")
        os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
        from services.ai import admin_tools, member_tools
        member = {t["function"]["name"] for t in member_tools.TOOLS}
        admin = {t["function"]["name"] for t in admin_tools.TOOLS}
        self.assertTrue({"market_reputation", "my_reviewable_offers"} <= member)
        self.assertIn("market_risk", admin)
        self.assertIn("market_risk", admin_tools._PERMISSION)


if __name__ == "__main__":
    unittest.main()
