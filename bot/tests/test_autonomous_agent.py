import json
import os
import unittest
from unittest.mock import AsyncMock, patch

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")

from db.rpc import RPCResult
from services.agent import config, github, merge, reviewer, tools
from services.agent.report import bar


class GithubGuardTests(unittest.TestCase):
    def test_branch_rules(self):
        self.assertTrue(github.valid_branch("agent/fix-menu-1122-1500"))
        for bad in ["PRISMA", "main", "agent/", "agent/../x", "feat/x", "agent/A B"]:
            self.assertFalse(github.valid_branch(bad), bad)
        self.assertTrue(github.valid_branch(github.new_branch_name("Покращити меню")))

    def test_write_paths(self):
        self.assertIsNone(github.check_write_path(".github/workflows/ci.yml"))
        self.assertIsNone(github.check_write_path("render.env"))
        self.assertIsNone(github.check_write_path("bot/.env"))
        self.assertEqual(github.check_write_path("bot/main.py"), "bot/main.py")

    def test_validate_files(self):
        self.assertIsNotNone(github.validate_files([])[1])
        self.assertIsNotNone(github.validate_files([{"path": "a.py", "content": "x"}] * 2)[1])
        self.assertIsNotNone(github.validate_files([{"path": "a.py", "content": 5}])[1])
        ok, err = github.validate_files([{"path": "a.py", "content": "x"}, {"path": "b.py", "delete": True}])
        self.assertIsNone(err)
        self.assertEqual(len(ok), 2)

    def test_checks_summary(self):
        runs = [{"status": "completed", "conclusion": "success", "name": "a"}, {"status": "completed", "conclusion": "failure", "name": "b"},
                {"status": "completed", "conclusion": "skipped", "name": "c"}, {"status": "in_progress", "name": "d"}]
        s = github.summarize_checks(runs)
        self.assertEqual((s["passed"], s["failed"], s["pending"], s["health_pct"]), (1, 1, 1, 33))
        self.assertEqual(github.summarize_checks([])["health_pct"], 100)

    def test_classify(self):
        k = github.classify_paths(["supabase/migrations/1.sql", "bot/services/agent/brain.py", "bot/x.py"])
        self.assertEqual(len(k["refused"]), 1)
        self.assertEqual(len(k["self"]), 1)


class WebGuardTests(unittest.TestCase):
    def test_only_allowlisted_https(self):
        self.assertIsNone(tools._host_ok("http://docs.python.org/"))
        self.assertIsNone(tools._host_ok("https://evil.example.com/"))
        self.assertIsNone(tools._host_ok("https://docs.python.org.evil.com/"))
        self.assertIsNone(tools._host_ok("https://user@docs.python.org/"))
        self.assertIsNone(tools._host_ok("https://docs.python.org:8443/"))


class ReviewerTests(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(reviewer.parse_verdict('x {"verdict":"ok","notes":"fine"} y')["verdict"], "OK")
        self.assertEqual(reviewer.parse_verdict("garbage")["verdict"], "RISKS")
        self.assertEqual(reviewer.parse_verdict('{"verdict":"DROP"}')["verdict"], "RISKS")


class BarTests(unittest.TestCase):
    def test_bar(self):
        self.assertTrue(bar(50).endswith("50%"))
        self.assertTrue(bar(250).endswith("100%"))


def _info(**kw):
    base = {"number": 7, "state": "open", "merged": False, "title": "t", "head_ref": "agent/x-0101-0000", "head_sha": "abc",
            "paths": ["bot/a.py"]}
    base.update(kw)
    return base


GREEN = {"total": 2, "passed": 2, "failed": 0, "pending": 0, "failing": []}


class MergeGateTests(unittest.IsolatedAsyncioTestCase):
    async def _eval(self, info, ci=GREEN, review=None, owner=False, override=False):
        goals = [{"pr_number": 7, "review": review or {}}]
        with patch.object(github, "pr_info", AsyncMock(return_value=info)), patch.object(github, "ci", AsyncMock(return_value=ci)), \
                patch.object(merge.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=goals))):
            return await merge.evaluate(7, owner=owner, override=override)

    async def test_green_ok(self):
        self.assertTrue((await self._eval(_info()))[0])

    async def test_refusals(self):
        self.assertFalse((await self._eval(_info(merged=True)))[0])
        self.assertFalse((await self._eval(_info(head_ref="feat/x")))[0])
        self.assertFalse((await self._eval(_info(paths=["supabase/migrations/1.sql"])))[0])
        self.assertFalse((await self._eval(_info(), ci={**GREEN, "pending": 1}))[0])
        self.assertFalse((await self._eval(_info(), ci={**GREEN, "failed": 1}))[0])

    async def test_block_needs_owner_override(self):
        review = {"verdict": "BLOCK"}
        self.assertFalse((await self._eval(_info(), review=review, owner=True))[0])
        self.assertFalse((await self._eval(_info(), review=review, owner=False, override=True))[0])
        self.assertTrue((await self._eval(_info(), review=review, owner=True, override=True))[0])

    def test_can_merge(self):
        self.assertTrue(merge.can_merge(1, ["*"]))
        self.assertFalse(merge.can_merge(1, ["bans.view"]))
        self.assertTrue(merge.can_merge(2, ["ops.manage"]))  # head admin without the "*" permission
        with patch.object(config, "MERGE_ADMIN_IDS", {5}):
            self.assertTrue(merge.can_merge(5, []))


class CommitToolTests(unittest.IsolatedAsyncioTestCase):
    async def test_commit_needs_goal_and_blocks_workflows(self):
        ctx = tools.Ctx(bot=None)
        with patch.object(tools, "_day_counter", AsyncMock(return_value=0)):
            self.assertIn("error", json.loads(await tools.run_tool(ctx, "commit", {"message": "m", "files": [{"path": ".github/w.yml", "content": "x"}]})))
            ctx.goal = {"id": 1, "title": "T", "branch": None}
            with patch.object(tools.rpc, "bot_agent_goal_save", AsyncMock(return_value=RPCResult(data={}))), \
                    patch.object(github, "ensure_branch", AsyncMock(return_value=("sha", None))), \
                    patch.object(github, "commit_files", AsyncMock(return_value=("abcdef1234567", None))), \
                    patch.object(github, "open_pr", AsyncMock(return_value=({"number": 9}, None))), \
                    patch.object(tools, "bump", AsyncMock()):
                out = json.loads(await tools.run_tool(ctx, "commit", {"message": "m", "files": [{"path": "bot/a.py", "content": "x"}]}))
        self.assertTrue(out["ok"])
        self.assertEqual(out["pr"], 9)
        self.assertTrue(ctx.goal["branch"].startswith("agent/"))

    async def test_daily_commit_cap(self):
        ctx = tools.Ctx(bot=None, goal={"id": 1, "title": "T"})
        with patch.object(tools, "_day_counter", AsyncMock(return_value=config.MAX_COMMITS_PER_DAY)):
            out = json.loads(await tools.run_tool(ctx, "commit", {"message": "m", "files": [{"path": "a.py", "content": "x"}]}))
        self.assertIn("error", out)

    async def test_unknown_tool_and_say_limit(self):
        ctx = tools.Ctx(bot=None)
        self.assertIn("error", json.loads(await tools.run_tool(ctx, "rm_rf", {})))
        ctx.says = config.MAX_SAYS_PER_CYCLE
        self.assertIn("error", json.loads(await tools.run_tool(ctx, "say", {"text": "hi"})))


if __name__ == "__main__":
    unittest.main()


class ReadableReportTests(unittest.IsolatedAsyncioTestCase):
    def test_labels_are_russian_and_short(self):
        self.assertTrue(tools.label("repo_read", {"path": "bot/main.py"}).startswith("📖 Читаю"))
        self.assertIn("Коммит", tools.label("commit", {"message": "x" * 200}))
        self.assertLessEqual(len(tools.label("commit", {"message": "x" * 200})), 80)

    def test_fallback_summary(self):
        from services.agent import brain
        ctx = tools.Ctx(bot=None)
        self.assertIn("ничего нового", brain._fallback_summary(ctx))
        ctx.counts = {"repo_read": 3, "commit": 1}
        text = brain._fallback_summary(ctx)
        self.assertIn("3 файлов", text)
        self.assertIn("1 изменений", text)

    def test_live_text(self):
        from services.agent import report
        ctx = tools.Ctx(bot=None, goal={"title": "Цель <b>", "progress_pct": 40})
        ctx.actions = ["📖 Читаю a.py"]
        ctx.step = 2
        text = report.live_text(ctx, 14)
        self.assertIn("шаг 2/14", text)
        self.assertIn("&lt;b&gt;", text)
        self.assertIn("40%", text)

    async def test_compact_queue_and_detail(self):
        from services.agent import report
        done = [{"id": 2, "title": "Вторая", "pr_number": 9, "progress_pct": 100, "health_pct": 100, "expected": "вторая задача",
                 "review": {"verdict": "OK", "plain": "Второе улучшение."}, "branch": "agent/b-1-1"},
                {"id": 1, "title": "Первая", "pr_number": 5, "progress_pct": 100, "health_pct": 75, "expected": "первая задача",
                 "review": {"verdict": "RISKS", "notes": "есть риск", "plain": "Первое улучшение в файле bot/a.py."}, "branch": "agent/a-1-1"}]
        active = [{"id": 3, "title": "Текущая работа", "expected": "сделать что-то", "progress_pct": 40}]

        async def goals(status=None, limit=20):
            return RPCResult(data=done if status == "done" else (active if status == "active" else []))

        with patch.object(report.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={"next_step": "дальше"}))), \
                patch.object(report.rpc, "bot_agent_goals_list", goals), \
                patch.object(github, "preview_url", AsyncMock(return_value=None)), \
                patch.object(github, "_repo", lambda: ("o/r", None)):
            text, markup = await report.build()
            detail, dmarkup = await report.detail(5)
        self.assertLess(text.index("№1 · Первое улучшение"), text.index("№2 · Второе улучшение"))  # oldest PR is №1
        self.assertIn("40%", text)
        self.assertNotIn("bot/a.py", text)
        self.assertLess(len(text), 900)
        buttons = [b.callback_data for row in markup.inline_keyboard for b in row]
        self.assertEqual(buttons[:2], ["agent:open:5", "agent:open:9"])
        self.assertTrue(detail.startswith("<b>№1 ·"))
        self.assertEqual([b.callback_data for b in dmarkup.inline_keyboard[0]], ["agent:merge:5", "agent:reject:5"])
        # after №1 is handled, the former №2 becomes №1
        done.pop(1)
        with patch.object(report.rpc, "bot_agent_goals_list", goals):
            text2, _ = await report.build()
        self.assertIn("№1 · Второе улучшение", text2)


class RejectTests(unittest.IsolatedAsyncioTestCase):
    async def test_reject_closes_and_remembers(self):
        goals = [{"id": 4, "pr_number": 7, "title": "Т"}]
        saved = {}

        async def save(gid, patch):
            saved.update(patch)
            return RPCResult(data={})

        with patch.object(github, "pr_info", AsyncMock(return_value=_info(number=7))), patch.object(github, "close_pr", AsyncMock(return_value=None)), \
                patch.object(merge.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=goals))), \
                patch.object(merge.rpc, "bot_agent_goal_save", save), patch.object(merge.rpc, "bot_agent_mem_add", AsyncMock(return_value=RPCResult(data=1))), \
                patch.object(merge.rpc, "bot_agent_journal_add", AsyncMock(return_value=RPCResult(data=1))):
            ok, _ = await merge.reject(7)
        self.assertTrue(ok)
        self.assertEqual(saved["status"], "dropped")
        with patch.object(github, "pr_info", AsyncMock(return_value=_info(head_ref="feat/x"))):
            self.assertFalse((await merge.reject(7))[0])


class EditToolTests(unittest.IsolatedAsyncioTestCase):
    async def _run(self, text, old, new):
        ctx = tools.Ctx(bot=None, goal={"id": 1, "title": "T", "branch": "agent/t-1-1", "head_sha": "x"})
        captured = {}

        async def fake_commit(c, message, files):
            captured["files"] = files
            return {"ok": True}

        with patch.object(github, "read_raw", AsyncMock(return_value=(text, None))), patch.object(tools, "_commit", fake_commit):
            out = json.loads(await tools.run_tool(ctx, "edit", {"path": "bot/a.py", "old_str": old, "new_str": new, "message": "m"}))
        return out, captured

    async def test_unique_replace(self):
        out, cap = await self._run("a = 1\nb = 2\n", "b = 2", "b = 3")
        self.assertTrue(out["ok"])
        self.assertEqual(cap["files"][0]["content"], "a = 1\nb = 3\n")

    async def test_ambiguous_or_missing(self):
        self.assertIn("error", (await self._run("x\nx\n", "x", "y"))[0])
        self.assertIn("error", (await self._run("x\n", "zzz", "y"))[0])
        self.assertIn("error", (await self._run("x\n", "x", "x"))[0])

    async def test_repeated_reads_are_refused(self):
        ctx = tools.Ctx(bot=None)
        with patch.object(github, "read", AsyncMock(return_value={"path": "a", "content": "c"})):
            first = json.loads(await tools.run_tool(ctx, "repo_read", {"path": "a"}))
            second = json.loads(await tools.run_tool(ctx, "repo_read", {"path": "a"}))
        self.assertNotIn("error", first)
        self.assertIn("error", second)

    def test_act_only_toolset_has_no_reads(self):
        names = {t["function"]["name"] for t in tools.act_schemas()}
        self.assertTrue({"edit", "commit", "finish_cycle"} <= names)
        self.assertFalse(names & tools.READ_ONLY)


class GuardTests(unittest.IsolatedAsyncioTestCase):
    def test_similar_titles(self):
        self.assertTrue(tools._similar("Добавить валидацию Telegram ID в сервисах", "валидацию Telegram ID добавить в сервисы бота"))
        self.assertFalse(tools._similar("Кнопка гайд в меню", "Проверка ников игроков"))

    async def test_goal_new_refused_when_queue_full(self):
        waiting = [{"pr_number": n, "merged_at": None} for n in range(1, config.MAX_WAITING + 1)]

        async def goals(status=None, limit=20):
            return RPCResult(data=[] if status == "active" else waiting)

        ctx = tools.Ctx(bot=None)
        with patch.object(tools.rpc, "bot_agent_goals_list", goals):
            out = json.loads(await tools.run_tool(ctx, "goal_new", {"title": "Новая", "expected": "x"}))
        self.assertIn("error", out)

    async def test_read_cap(self):
        ctx = tools.Ctx(bot=None)
        ctx.counts["repo_read"] = 11
        out = json.loads(await tools.run_tool(ctx, "repo_read", {"path": "a.py"}))
        self.assertIn("лимит", out["error"])

    def test_strip_tech(self):
        from services.agent import brain
        self.assertEqual(brain.strip_tech("Правка в bot/a.py и `Foo` готова"), "Правка в и готова")


class IdeaModeTests(unittest.TestCase):
    def test_idea_toolset_cannot_write_code(self):
        names = {t["function"]["name"] for t in tools.idea_schemas()}
        self.assertTrue({"memory_save", "finish_cycle", "repo_read"} <= names)
        self.assertFalse(names & {"commit", "edit", "goal_new"})


class RunCycleRegressionTests(unittest.IsolatedAsyncioTestCase):
    async def _run(self, active):
        from services.agent import brain, memory

        async def goals(status=None, limit=20):
            return RPCResult(data=active if status == "active" else [])

        with patch.object(brain.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={}))), \
                patch.object(brain.client, "is_configured", lambda role="user": True), \
                patch.object(brain, "_budget_ok", AsyncMock(return_value=True)), \
                patch.object(brain.rpc, "bot_agent_goals_list", goals), \
                patch.object(brain.rpc, "bot_agent_inbox_take", AsyncMock(return_value=RPCResult(data=[]))), \
                patch.object(brain.report, "live", AsyncMock()), \
                patch.object(brain.rpc, "bot_agent_journal_add", AsyncMock(return_value=RPCResult(data=1))), \
                patch.object(memory, "build_context", AsyncMock(return_value="ctx")), \
                patch.object(brain.github, "tree_overview", AsyncMock(return_value="tree")), \
                patch.object(brain, "_ask", AsyncMock(side_effect=brain.client.AIError("down"))):
            return await brain.run_cycle(bot=None)

    async def test_cycle_runs_with_an_active_goal(self):
        # regression: the inbox was only read when there was no active goal -> UnboundLocalError on every cycle
        out = await self._run([{"id": 1, "title": "T", "progress_pct": 10}])
        self.assertFalse(out["ok"])
        self.assertIn("ИИ недоступен", out["summary"])

    async def test_cycle_runs_without_a_goal(self):
        out = await self._run([])
        self.assertIn("ИИ недоступен", out["summary"])
