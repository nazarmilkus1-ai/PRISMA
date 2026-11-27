import json
import unittest
from unittest.mock import AsyncMock, patch

from db.rpc import RPCResult
from services.agent import checks, tools


class BannedThemeMatch(unittest.TestCase):
    def test_all_parts_must_occur(self):
        themes = ["except+лог"]
        self.assertEqual(checks.banned_theme("Добавить лог в except digest.py", themes), "except+лог")
        self.assertIsNone(checks.banned_theme("Написать тесты для сервиса points", themes))
        self.assertIsNone(checks.banned_theme("Разобрать except в handlers", themes))  # only one part

    def test_single_word_theme_and_case(self):
        self.assertEqual(checks.banned_theme("Добавить LOGGER в модуль", ["logger"]), "logger")

    def test_garbage_themes_are_ignored(self):
        self.assertIsNone(checks.banned_theme("что угодно", None))
        self.assertIsNone(checks.banned_theme("что угодно", "except"))
        self.assertIsNone(checks.banned_theme("что угодно", ["", "+", "  "]))


class GoalNewRefusesBannedTheme(unittest.IsolatedAsyncioTestCase):
    async def _goal_new(self, args, themes):
        save = AsyncMock(return_value=RPCResult(data={"id": 9}))
        with patch.object(tools.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[]))), \
             patch.object(tools.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={"banned_themes": themes}))), \
             patch.object(tools.rpc, "bot_agent_goal_save", save):
            out = json.loads(await tools.run_tool(tools.Ctx(bot=None), "goal_new", args))
        return out, save

    async def test_closed_theme_is_refused_and_nothing_saved(self):
        out, save = await self._goal_new({"title": "Добавить logger.error в except digest.py", "expected": "x"}, ["except+logger"])
        self.assertIn("error", out)
        self.assertIn("except+logger", out["error"])
        save.assert_not_awaited()

    async def test_theme_in_the_reason_counts_too(self):
        out, save = await self._goal_new({"title": "Мелкая правка", "why": "в except нет logger", "expected": "x"}, ["except+logger"])
        self.assertIn("error", out)
        save.assert_not_awaited()

    async def test_other_theme_is_accepted(self):
        out, save = await self._goal_new({"title": "Тесты для сервиса clans", "expected": "x"}, ["except+logger"])
        self.assertTrue(out["ok"])
        save.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
