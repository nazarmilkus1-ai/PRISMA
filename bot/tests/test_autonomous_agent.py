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

    async def test_build_report_sections(self):
        from services.agent import report
        goals_done = [{"id": 1, "title": "Кнопка", "pr_number": 5, "progress_pct": 100, "health_pct": 100, "expected": "кнопка в меню",
                       "review": {"verdict": "OK", "notes": "норм"}, "branch": "agent/x-1-1"}]

        async def goals(status=None, limit=20):
            return RPCResult(data=goals_done if status == "done" else [])

        with patch.object(report.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={"next_step": "следующая задача"}))), \
                patch.object(report.rpc, "bot_agent_journal_recent", AsyncMock(return_value=RPCResult(data=[{"body": "добавил кнопку"}]))), \
                patch.object(report.rpc, "bot_agent_goals_list", goals), \
                patch.object(report.rpc, "bot_agent_mem_count", AsyncMock(return_value=RPCResult(data=3))), \
                patch.object(github, "_repo", lambda: ("o/r", None)):
            text, markup = await report.build()
        for part in ("Что сделал", "Что дальше", "Готово, ждёт вашей кнопки", "Слить", "В памяти заметок: 3", "Второй ИИ проверил"):
            self.assertIn(part, text if part != "Слить" else str(markup))
