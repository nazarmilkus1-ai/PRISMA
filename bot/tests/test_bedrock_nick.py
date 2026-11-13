import unittest

from utils.helpers import bedrock_gamertag, bedrock_server_nick, validate_minecraft_nick


class BedrockGamertagTests(unittest.TestCase):
    def test_space_becomes_underscore_with_prefix(self):
        tag = bedrock_gamertag("D1lan ok")
        self.assertEqual(tag, "D1lan ok")
        self.assertEqual(bedrock_server_nick(tag), ".D1lan_ok")

    def test_typed_forms_are_normalized(self):
        self.assertEqual(bedrock_gamertag("  .D1lan   ok  "), "D1lan ok")
        self.assertEqual(bedrock_gamertag("D1lan ok#1234"), "D1lan ok")

    def test_limits(self):
        self.assertIsNone(bedrock_gamertag("ab"))
        self.assertIsNone(bedrock_gamertag("a" * 16))  # "." + 16 would exceed Floodgate's 16 characters
        self.assertIsNotNone(bedrock_gamertag("a" * 15))
        self.assertIsNone(bedrock_gamertag("Bad|Name"))
        self.assertIsNone(bedrock_gamertag("Жора ok"))

    def test_server_form_never_exceeds_16_characters(self):
        self.assertLessEqual(len(bedrock_server_nick(bedrock_gamertag("a" * 15))), 16)


class ValidateByPlatformTests(unittest.TestCase):
    def test_platform_not_chosen_yet_accepts_either_form(self):
        self.assertTrue(validate_minecraft_nick("D1lan ok")[0])
        self.assertTrue(validate_minecraft_nick("Steve_01")[0])
        self.assertFalse(validate_minecraft_nick("ab")[0])
        self.assertFalse(validate_minecraft_nick("bad|nick")[0])

    def test_java_rejects_spaces(self):
        ok, error = validate_minecraft_nick("D1lan ok", "java")
        self.assertFalse(ok)
        self.assertIn("без пробелов", error)

    def test_bedrock_accepts_spaces(self):
        self.assertTrue(validate_minecraft_nick("D1lan ok", "Bedrock")[0])

    def test_java_length_limit_kept(self):
        self.assertFalse(validate_minecraft_nick("a" * 17, "java")[0])
        self.assertTrue(validate_minecraft_nick("a" * 16, "java")[0])


if __name__ == "__main__":
    unittest.main()
