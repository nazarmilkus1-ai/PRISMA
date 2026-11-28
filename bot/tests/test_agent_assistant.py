import json
import os
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")

from db.rpc import RPCResult
from services.agent import autopilot, brain, chat, config, jobs, loop, report, tools
from services.ai import client


def assistant():
    return patch.object(config, "CODE_ACCESS", False)


class Switch(unittest.TestCase):
    def test_default_is_the_assistant_without_code_access(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("AGENT_CODE_ACCESS", None)
            self.assertFalse(config._flag("AGENT_CODE_ACCESS"))

    def test_flag_values(self):
        for value in ("1", "true", "ON", "yes"):
            with patch.dict(os.environ, {"AGENT_CODE_ACCESS": value}):
                self.assertTrue(config._flag("AGENT_CODE_ACCESS"), value)
        for value in ("0", "", "no", "off"):
            with patch.dict(os.environ, {"AGENT_CODE_ACCESS": value}):
                self.assertFalse(config._flag("AGENT_CODE_ACCESS"), value)


class NoWriteTools(unittest.IsolatedAsyncioTestCase):
    def test_assistant_toolset_has_nothing_that_writes(self):
        names = {t["function"]["name"] for t in tools.assistant_schemas()}
        self.assertFalse(names & tools.WRITE_TOOLS)
        self.assertTrue({"repo_read", "repo_search", "render_logs", "say", "finish_cycle"} <= names)

    async def test_write_tools_are_refused_even_if_the_model_asks(self):
        calls = AsyncMock()
        with assistant(), patch.object(tools, "_commit", calls, create=True), patch.object(tools.github, "commit_files", calls, create=True):
            for name in sorted(tools.WRITE_TOOLS):
                out = json.loads(await tools.run_tool(tools.Ctx(bot=None), name, {"path": "bot/x.py", "old_str": "a", "new_str": "b", "message": "m", "files": [], "title": "t", "expected": "e"}))
                self.assertIn("помощник", out["error"], name)
        calls.assert_not_awaited()

    async def test_tasks_cannot_be_queued(self):
        with assistant(), patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock()) as listed, patch.object(jobs.rpc, "bot_agent_goal_save", AsyncMock()) as save:
            goal, note = await jobs.add_task("добавить кнопку правил в меню", "@adm")
        self.assertIsNone(goal)
        self.assertIn("не меняю код", note)
        listed.assert_not_awaited()
        save.assert_not_awaited()

    async def test_autopilot_and_maintenance_do_nothing(self):
        with assistant(), patch.object(autopilot.rpc, "bot_agent_goals_list", AsyncMock()) as listed, patch.object(brain.rpc, "bot_agent_state_get", AsyncMock()) as state:
            await autopilot.step(None, {"auto_merge": True})
            await brain.maintain(None)
        listed.assert_not_awaited()
        state.assert_not_awaited()

    async def test_worker_cadence_and_reports(self):
        with assistant():
            self.assertEqual(await loop._cycle_seconds(), config.ASSISTANT_CYCLE_SECONDS)
            self.assertIs(report.help_text(), report.ASSISTANT_HELP)
        self.assertIs(report.help_text(), report.HELP)  # access on: the old help


class AssistantCycle(unittest.IsolatedAsyncioTestCase):
    async def _run(self, state, inbox, asks):
        journal = AsyncMock()
        patch_state = AsyncMock()
        ask = AsyncMock(side_effect=asks)

        async def fake_run_tool(ctx, name, args):
            if name == "finish_cycle":
                ctx.finished, ctx.summary = True, args.get("summary", "")
            return "{}"

        with assistant(), patch.object(brain.rpc, "bot_agent_inbox_take", AsyncMock(return_value=RPCResult(data=inbox))), \
                patch.object(brain.rpc, "bot_agent_state_patch", patch_state), patch.object(brain.rpc, "bot_agent_journal_add", journal), \
                patch.object(brain.memory, "build_context", AsyncMock(return_value="ctx")), patch.object(brain, "_ask", ask), \
                patch.object(brain.tools, "run_tool", fake_run_tool):
            result = await brain._assistant_cycle(None, state)
        return result, ask, journal, patch_state

    async def test_nothing_to_do_costs_no_ai_call(self):
        import time
        result, ask, journal, _ = await self._run({"last_check": time.time()}, [], [])
        self.assertTrue(result["ok"])
        ask.assert_not_awaited()
        journal.assert_not_awaited()

    async def test_admin_question_is_answered_with_read_only_tools(self):
        import time
        inbox = [{"is_admin": True, "username": "adm", "text": "что в логах за час?"}]
        finish = {"role": "assistant", "content": "", "tool_calls": [{"id": "1", "function": {"name": "finish_cycle", "arguments": json.dumps({"summary": "ответил про логи"})}}]}
        result, ask, journal, _ = await self._run({"last_check": time.time()}, inbox, [finish])
        offered = {t["function"]["name"] for t in ask.await_args.args[1]}
        self.assertFalse(offered & tools.WRITE_TOOLS)
        self.assertTrue(result["ok"])
        self.assertIn("ответил про логи", result["summary"])
        self.assertEqual(journal.await_args.args[1], "ответил про логи")

    async def test_scheduled_check_remembers_when_it_looked(self):
        finish = {"role": "assistant", "content": "", "tool_calls": [{"id": "1", "function": {"name": "finish_cycle", "arguments": json.dumps({"summary": "прод в порядке"})}}]}
        result, ask, _, patch_state = await self._run({}, [], [finish])
        self.assertIn("last_check", patch_state.await_args_list[0].args[0])
        self.assertIn("Плановая проверка", ask.await_args.args[0][1]["content"])
        self.assertTrue(result["ok"])

    async def test_ai_outage_is_reported_not_raised(self):
        result, _, journal, patch_state = await self._run({}, [], [client.AIError("down")])
        self.assertFalse(result["ok"])
        self.assertIn("ai_wait_until", patch_state.await_args.args[0])
        journal.assert_not_awaited()

    async def test_run_cycle_hands_over_to_the_assistant(self):
        handed = AsyncMock(return_value={"ok": True, "summary": "x"})
        state = {"paused": False}
        with assistant(), patch.object(brain, "_assistant_cycle", handed), patch.object(brain.client, "is_configured", return_value=True), \
                patch.object(brain.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data=state))), patch.object(brain, "_budget_ok", AsyncMock(return_value=True)), \
                patch.object(brain, "_choose_work", AsyncMock(side_effect=AssertionError("must not choose code work"))):
            await brain.run_cycle(None)
        handed.assert_awaited_once()


class AssistantChat(unittest.IsolatedAsyncioTestCase):
    async def test_chat_uses_the_assistant_prompt_and_status(self):
        seen = {}

        async def fake_chat(messages, **kw):
            seen["system"] = messages[0]["content"]
            seen["user"] = messages[1]["content"]
            return {"content": json.dumps({"reply": "Код не меняю", "task": ""})}

        with assistant(), patch.object(chat.client, "is_configured", return_value=True), patch.object(chat.client, "chat", fake_chat), \
                patch.object(chat.client, "agent_models", return_value=["m"]), \
                patch.object(chat.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={}))), \
                patch.object(chat.rpc, "bot_agent_journal_recent", AsyncMock(return_value=RPCResult(data=[{"body": "проверил прод"}]))):
            reply, task = await chat.answer("добавь кнопку", "@adm", True)
        self.assertIn("НЕ меняешь", seen["system"])
        self.assertIn("помощник админов", seen["user"])
        self.assertEqual((reply, task), ("Код не меняю", ""))


class AssistantTopic(unittest.IsolatedAsyncioTestCase):
    def _message(self, text):
        reply = AsyncMock()
        bot = SimpleNamespace(me=AsyncMock(return_value=SimpleNamespace(id=99, username="prisma_bot")))
        return SimpleNamespace(text=text, message_id=10, reply=reply, reply_to_message=None, message_thread_id=config.THREAD_ID, bot=bot,
                               from_user=SimpleNamespace(id=1, username="adm", full_name="Adm")), reply

    async def test_question_that_needs_a_look_wakes_the_assistant_and_queues_nothing(self):
        from handlers import agent_topic
        agent_topic._last_ack.clear()
        message, reply = self._message("@prisma_bot почему упал бот?")
        wake, add = AsyncMock(), AsyncMock()
        with assistant(), patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True})), \
                patch.object(agent_topic.rpc, "bot_agent_inbox_add", AsyncMock()), patch.object(agent_topic.rpc, "bot_agent_mem_add", AsyncMock()), \
                patch.object(agent_topic.chat, "answer", AsyncMock(return_value=("Гляну логи", "почему упал бот"))), \
                patch.object(agent_topic.jobs, "add_task", add), patch.object(agent_topic.jobs, "wake", wake):
            await agent_topic.ingest(message)
        self.assertIn("отвечу здесь", reply.await_args.args[0])
        wake.assert_awaited_once()
        add.assert_not_awaited()

    async def test_task_command_explains_the_new_role(self):
        from handlers import agent_topic
        message, reply = self._message("/task добавить кнопку правил в меню")
        with assistant(), patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True, "permissions": ["*"]})):
            await agent_topic.admin_commands(message)
        self.assertIn("не меняю код", reply.await_args.args[0])

    async def test_agent_auto_is_explained(self):
        from handlers import agent_topic
        message, reply = self._message("/agent_auto on")
        patch_state = AsyncMock()
        with assistant(), patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True, "permissions": ["*"]})), \
                patch.object(agent_topic.rpc, "bot_agent_state_patch", patch_state):
            await agent_topic.admin_commands(message)
        patch_state.assert_not_awaited()
        self.assertIn("не нужно", reply.await_args.args[0])


if __name__ == "__main__":
    unittest.main()
