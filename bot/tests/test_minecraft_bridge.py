import unittest
from bot.services.minecraft_bridge import _clean_text, _looks_like_group_command

class TestMinecraftBridge(unittest.TestCase):
    def test_clean_text_basic(self):
        self.assertEqual(_clean_text("  Hello   world  "), "Hello world")
        self.assertEqual(_clean_text("\t\n  foo bar  "), "foo bar")
        self.assertEqual(_clean_text(""), "")

    def test_clean_text_max_length(self):
        long_text = "a" * 600
        self.assertEqual(_clean_text(long_text), "")
        self.assertEqual(_clean_text("a" * 501), "")

    def test_looks_like_group_command_group_commands(self):
        self.assertTrue(_looks_like_group_command("warn"))
        self.assertTrue(_looks_like_group_command("WARN"))
        self.assertTrue(_looks_like_group_command("  warn  "))
        self.assertTrue(_looks_like_group_command("warn:"))
        self.assertTrue(_looks_like_group_command("/warn"))

    def test_looks_like_group_command_non_group(self):
        self.assertFalse(_looks_like_group_command("hello"))
        self.assertFalse(_looks_like_group_command("player"))

    def test_looks_like_group_command_start_symbols(self):
        self.assertTrue(_looks_like_group_command("/"))
        self.assertTrue(_looks_like_group_command("+"))
        self.assertTrue(_looks_like_group_command("-"))
        self.assertTrue(_looks_like_group_command(" /"))
        self.assertTrue(_looks_like_group_command("+foo"))

    def test_looks_like_group_command_empty(self):
        self.assertTrue(_looks_like_group_command(""))