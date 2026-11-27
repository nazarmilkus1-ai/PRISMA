import os
import unittest
from unittest.mock import AsyncMock, patch

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")

from db import rpc as db_rpc
from db.rpc import RPCResult
from services.agent import brain, config, jobs


def goal(**kw):
    return {"id": 7, "title": "Улучшить текст", "source": "agent", "pr_number": None, **kw}


class GoalCycleCap(unittest.IsolatedAsyncioTestCase):
    async def _run(self, g, state):
        save, patch_state, journal = AsyncMock(return_value=RPCResult(data={})), AsyncMock(), AsyncMock()
        with patch.object(brain.rpc, "bot_agent_goal_save", save), patch.object(brain.rpc, "bot_agent_state_patch", patch_state), \
                patch.object(brain.rpc, "bot_agent_journal_add", journal):
            over = await brain._goal_over_cap(state, g)
        return over, save, patch_state, journal

    async def test_counts_cycles_on_the_same_goal(self):
        over, save, patch_state, _ = await self._run(goal(), {"goal_cycle": {"id": 7, "n": 3}})
        self.assertFalse(over)
        self.assertEqual(patch_state.await_args.args[0], {"goal_cycle": {"id": 7, "n": 4}})
        save.assert_not_awaited()

    async def test_new_goal_starts_from_one(self):
        over, _, patch_state, _ = await self._run(goal(id=8), {"goal_cycle": {"id": 7, "n": 99}})
        self.assertFalse(over)
        self.assertEqual(patch_state.await_args.args[0], {"goal_cycle": {"id": 8, "n": 1}})

    async def test_goal_with_pr_is_finished_past_the_cap(self):
        over, save, patch_state, journal = await self._run(goal(pr_number=197), {"goal_cycle": {"id": 7, "n": config.MAX_GOAL_CYCLES}})
        self.assertTrue(over)
        self.assertEqual(save.await_args.args, (7, {"status": "done", "progress_pct": 100}))
        self.assertEqual(patch_state.await_args.args[0], {"goal_cycle": None})
        self.assertIn("PR остаётся", journal.await_args.args[1])

    async def test_goal_without_pr_is_dropped_past_the_cap(self):
        over, save, _, _ = await self._run(goal(), {"goal_cycle": {"id": 7, "n": config.MAX_GOAL_CYCLES}})
        self.assertTrue(over)
        self.assertEqual(save.await_args.args, (7, {"status": "dropped"}))

    async def test_people_tasks_and_rebuilds_have_no_cap(self):
        for source in jobs.QUEUE_SOURCES:
            over, save, patch_state, _ = await self._run(goal(source=source), {"goal_cycle": {"id": 7, "n": 500}})
            self.assertFalse(over)
            save.assert_not_awaited()
            patch_state.assert_not_awaited()

    async def test_choose_work_moves_on_after_the_cap(self):
        async def goals(status=None, limit=20):
            return RPCResult(data=[goal(pr_number=5)] if status == "active" else [])

        with patch.object(brain.rpc, "bot_agent_goals_list", goals), patch.object(brain.rpc, "bot_agent_goal_save", AsyncMock(return_value=RPCResult(data={}))), \
                patch.object(brain.rpc, "bot_agent_state_patch", AsyncMock()), patch.object(brain.rpc, "bot_agent_journal_add", AsyncMock()):
            chosen, _, _ = await brain._choose_work({"goal_cycle": {"id": 7, "n": config.MAX_GOAL_CYCLES}})
        self.assertIsNone(chosen)


class RpcDefaultRetries(unittest.TestCase):
    def test_reads_and_idempotent_calls_retry_once(self):
        for name in ("bot_get_community_chat_id", "bot_list_events", "get_public_module_states", "bot_agent_state_get", "bot_agent_state_patch",
                     "bot_claim_notifications", "mc_bridge_claim_for_telegram", "bot_set_onboarding_restriction_state", "bot_agent_claim"):
            self.assertEqual(db_rpc.default_retries(name), 1, name)

    def test_other_writes_are_never_retried_by_default(self):
        for name in ("bot_touch_user", "bot_lift_punishment", "bot_agent_goal_save", "bot_agent_mem_add", "pp_transfer"):
            self.assertEqual(db_rpc.default_retries(name), 0, name)


class RpcRetryBehaviour(unittest.IsolatedAsyncioTestCase):
    async def test_dropped_connection_on_a_read_is_retried(self):
        calls = []

        class Query:
            def execute(self):
                calls.append(1)
                if len(calls) == 1:
                    raise RuntimeError("Server disconnected")
                return type("R", (), {"data": {"ok": True}})()

        with patch.object(db_rpc.supabase, "rpc", lambda name, params: Query()), patch("db.rpc.asyncio.sleep", AsyncMock()):
            res = await db_rpc.call_rpc_async("bot_get_community_chat_id", {})
        self.assertEqual(res.data, {"ok": True})
        self.assertEqual(len(calls), 2)

    async def test_dropped_connection_on_a_write_is_not_repeated(self):
        calls = []

        class Query:
            def execute(self):
                calls.append(1)
                raise RuntimeError("Server disconnected")

        with patch.object(db_rpc.supabase, "rpc", lambda name, params: Query()), patch("db.rpc.asyncio.sleep", AsyncMock()):
            res = await db_rpc.call_rpc_async("bot_lift_punishment", {})
        self.assertTrue(res.error)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
