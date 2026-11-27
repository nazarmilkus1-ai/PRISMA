import os
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")

from services.minecraft_bridge import _clean_text, _looks_like_group_command


class CleanText(unittest.TestCase):
    def test_empty_string(self):
        self.assertEqual(_clean_text(""), "")

    def test_whitespace_and_control_chars(self):
        self.assertEqual(_clean_text("  \t\n"), "")
        self.assertEqual(_clean_text("\x00\x01"), "")

    def test_normal_text(self):
        self.assertEqual(_clean_text("Hello world"), "Hello world")

    def test_length_limit(self):
        long_text = "a" * 600
        self.assertEqual(_clean_text(long_text), "")

    def test_control_chars_removed(self):
        text = "Hello\x00world\x7f"
        self.assertEqual(_clean_text(text), "Hello world")


class LooksLikeGroupCommand(unittest.TestCase):
    def test_empty(self):
        self.assertTrue(_looks_like_group_command(""))

    def test_starts_with_special(self):
        self.assertTrue(_looks_like_group_command("/warn"))
        self.assertTrue(_looks_like_group_command("+ban"))
        self.assertTrue(_looks_like_group_command("-kick"))

    def test_valid_command(self):
        self.assertTrue(_looks_like_group_command("warn"))
        self.assertTrue(_looks_like_group_command("ban"))

    def test_invalid_command(self):
        self.assertFalse(_looks_like_group_command("hello"))
        self.assertFalse(_looks_like_group_command("moderator"))
