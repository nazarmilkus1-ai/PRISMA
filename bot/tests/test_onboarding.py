import os
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")

from services import onboarding


class DisplayName(unittest.TestCase):
    def test_prefers_first_name_then_full_name_then_username(self):
        self.assertEqual(onboarding._display_name({"first_name": "Аня", "full_name": "Аня К", "telegram_username": "anya"}), "Аня")
        self.assertEqual(onboarding._display_name({"full_name": "Аня К", "telegram_username": "anya"}), "Аня К")
        self.assertEqual(onboarding._display_name({"telegram_username": "anya"}), "anya")

    def test_falls_back_to_a_neutral_word(self):
        self.assertEqual(onboarding._display_name({}), "участник")
        self.assertEqual(onboarding._display_name({"first_name": "   "}), "участник")

    def test_collapses_whitespace_and_cuts_to_32_chars(self):
        self.assertEqual(onboarding._display_name({"first_name": "  Аня \n  К  "}), "Аня К")
        self.assertEqual(len(onboarding._display_name({"first_name": "я" * 100})), 32)


class Mention(unittest.TestCase):
    def test_valid_id_gives_a_link_with_escaped_name(self):
        text = onboarding._mention({"telegram_id": "42", "first_name": "<b>Аня</b>"})
        self.assertEqual(text, '<a href="tg://user?id=42">&lt;b&gt;Аня&lt;/b&gt;</a>')

    def test_bad_id_still_shows_the_person_not_an_error_text(self):
        # the digest lists people for admins: one broken row must not put an error sentence into the list
        for row in ({"telegram_id": "abc", "first_name": "Аня"}, {"first_name": "Аня"}, {"telegram_id": None, "first_name": "Аня"}):
            self.assertEqual(onboarding._mention(row), "Аня")

    def test_bad_id_name_is_escaped(self):
        self.assertEqual(onboarding._mention({"telegram_id": "x", "first_name": "<i>"}), "&lt;i&gt;")


class Stage(unittest.TestCase):
    def test_known_stage_is_normalised(self):
        self.assertEqual(onboarding._stage({"onboarding_stage": "not_opened"}), onboarding.NOT_OPENED)
        self.assertEqual(onboarding._stage({"onboarding_stage": "opened_no_application"}), onboarding.OPENED_NO_APPLICATION)

    def test_unknown_stage_is_derived_from_bot_started_at(self):
        self.assertEqual(onboarding._stage({}), onboarding.NOT_OPENED)
        self.assertEqual(onboarding._stage({"bot_started_at": "2026-11-01T10:00:00Z"}), onboarding.OPENED_NO_APPLICATION)


class DigestPages(unittest.TestCase):
    def test_empty_or_unusable_rows_give_no_pages(self):
        self.assertEqual(onboarding._format_digest_pages([]), [])
        self.assertEqual(onboarding._format_digest_pages([{"first_name": "без id"}, "не словарь", None]), [])

    def test_one_page_has_both_sections_and_the_total(self):
        rows = [
            {"telegram_id": 1, "first_name": "Аня"},
            {"telegram_id": 2, "first_name": "Борис", "bot_started_at": "2026-11-01T10:00:00Z"},
        ]
        pages = onboarding._format_digest_pages(rows)
        self.assertEqual(len(pages), 1)
        self.assertIn("Не открыли бота — 1", pages[0])
        self.assertIn("не подали заявку — 1", pages[0])
        self.assertIn("Всего: 2", pages[0])
        self.assertIn('tg://user?id=1', pages[0])

    def test_long_lists_are_split_under_the_telegram_limit(self):
        rows = [{"telegram_id": i, "first_name": f"Игрок{i:04d}" + "я" * 20} for i in range(1, 400)]
        pages = onboarding._format_digest_pages(rows)
        self.assertGreater(len(pages), 1)
        self.assertTrue(all(len(page) <= onboarding.TELEGRAM_MESSAGE_LIMIT + 200 for page in pages))
        self.assertIn(f"часть 1/{len(pages)}", pages[0])
        self.assertEqual(sum(page.count("tg://user?id=") for page in pages), 399)


if __name__ == "__main__":
    unittest.main()
