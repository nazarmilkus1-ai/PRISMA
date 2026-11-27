import unittest
import sys
import os
import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from bot.services.minecraft_bridge import _clean_text, _looks_like_group_command

class TestMinecraftBridge(unittest.TestCase):
    def test_clean_text_empty(self):
        self.assertEqual(_clean_text(""), "")

    def test_clean_text_whitespace(self):
        self.assertEqual(_clean_text("   \t\n"), "")

    def test_clean_text_normal(self):
        self.assertEqual(_clean_text("Hello world!"), "Hello world!")

    def test_clean_text_control_chars(self):
        text = "Hello\x00world\x7f!"
        result = _clean_text(text)
        self.assertEqual(result, "Helloworld!")

    def test_clean_text_too_long(self):
        long_text = "a" * 600
        self.assertEqual(_clean_text(long_text), "")

    def test_looks_like_group_command_recognized(self):
        self.assertTrue(_looks_like_group_command("warn"))
        self.assertTrue(_looks_like_group_command("WARN"))

    def test_looks_like_group_command_not_recognized(self):
        self.assertFalse(_looks_like_group_command("hello"))

    def test_looks_like_group_command_starts_with_slash(self):
        self.assertTrue(_looks_like_group_command("/warn"))

    def test_looks_like_group_command_starts_with_plus(self):
        self.assertTrue(_looks_like_group_command("+warn"))

    def test_looks_like_group_command_starts_with_minus(self):
        self.assertTrue(_looks_like_group_command("-\warn"))

    def test_looks_like_group_command_normal_text(self):
        self.assertFalse(_looks_like_group_command("some random text"))

if __name__ == "__main__":
    unittest.main()
