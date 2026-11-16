import unittest

from services.ai import client


class ProviderSpam(unittest.TestCase):
    def test_gate_and_advert_are_spam(self):
        self.assertTrue(client.looks_like_provider_spam("🚀 To use this bot, you must join our channel: https://t.me/campaignmudraofficial"))
        self.assertTrue(client.looks_like_provider_spam("👉 Undress girlfriend https://generai.org/telegram 🔥 Best AI Porn Gen"))

    def test_normal_answers_pass(self):
        self.assertFalse(client.looks_like_provider_spam("Привет! Канал сообщества: t.me/prisma_news"))
        self.assertFalse(client.looks_like_provider_spam(""))


if __name__ == "__main__":
    unittest.main()
