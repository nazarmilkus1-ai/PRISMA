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
from services.agent import brain, chat, checks, config, github, jobs, report, tools

UNITTEST_LOG = """2026-11-23T00:13:02.1Z test_ok (tests.test_a.A.test_ok) ... ok
2026-11-23T00:13:02.5Z ======================================================================
2026-11-23T00:13:02.5Z ERROR: test_bounded_memory (tests.test_quick.QuickTests.test_bounded_memory)
2026-11-23T00:13:02.5Z ----------------------------------------------------------------------
2026-11-23T00:13:02.5Z Traceback (most recent call last):
2026-11-23T00:13:02.5Z     raise ValueError(f"bad id {tg_id}")
2026-11-23T00:13:02.5Z ValueError: bad id 0
2026-11-23T00:13:02.5Z ----------------------------------------------------------------------
2026-11-23T00:13:02.5Z FAILED (errors=1)
2026-11-23T00:13:02.8Z ##[error]Process completed with exit code 1.
"""


class PrecheckTests(unittest.TestCase):
    def test_python_syntax_error_is_caught(self):
        out = checks.precheck([{"path": "bot/handlers/x.py", "content": "def broken(:\n    pass\n"}])
        self.assertIn("синтаксическая ошибка", out)
        self.assertIn("bot/handlers/x.py", out)

    def test_architecture_rule_in_services_but_not_in_tests(self):
        bad = {"path": "bot/services/x.py", "content": "cache = {}\ncache" + ".up" + "date({'a': 1})\n"}
        self.assertIn("insert/update/delete", checks.precheck([bad]))
        self.assertIsNone(checks.precheck([{**bad, "path": "bot/tests/test_x.py"}]))
        self.assertIsNone(checks.precheck([{"path": "bot/handlers/x.py", "content": "d = {}\nd |= {'a': 1}\n"}]))

    def test_json_deletes_and_conflict_markers(self):
        self.assertIn("JSON", checks.precheck([{"path": "site/a.json", "content": "{bad"}]))
        self.assertIsNone(checks.precheck([{"path": "site/a.json", "content": '{"a": 1}'}]))
        self.assertIsNone(checks.precheck([{"path": "bot/a.py", "delete": True}]))
        self.assertIn("конфликта", checks.precheck([{"path": "docs/a.md", "content": "a\n<<<<<<< HEAD\nb\n"}]))
        self.assertIsNone(checks.precheck([{"path": "site/src/a.tsx", "content": "export const a = 1"}]))


class FailureExcerptTests(unittest.TestCase):
    def test_unittest_failure_is_trimmed_to_the_point(self):
        text = checks.failure_excerpt(UNITTEST_LOG)
        self.assertIn("ERROR: test_bounded_memory", text)
        self.assertIn("ValueError: bad id 0", text)
        self.assertIn("FAILED (errors=1)", text)
        self.assertNotIn("test_ok", text)
        self.assertNotIn("2026-11-23", text)

    def test_other_tools_and_empty(self):
        log = "\n".join(["noise"] * 5 + ["src/a.ts(3,5): error TS2322: Type 'string' is not assignable", "more"] + ["tail"] * 30)
        self.assertIn("error TS2322", checks.failure_excerpt(log))
        self.assertEqual(checks.failure_excerpt(""), "")
        self.assertIn("plain tail", checks.failure_excerpt("plain tail"))


class PlanTests(unittest.TestCase):
    def test_norm_tasks_accepts_strings_and_old_dicts(self):
        out = checks.norm_tasks(["Найти место", {"t": "Правка", "done": True}, {"title": "Тест"}, 5, "  "])
        self.assertEqual([t["t"] for t in out], ["Найти место", "Правка", "Тест"])
        self.assertEqual([t["done"] for t in out], [False, True, False])
        self.assertEqual(checks.norm_tasks(None), [])

    def test_progress_comes_from_steps(self):
        steps = lambda *flags: [{"t": f"s{i}", "done": f} for i, f in enumerate(flags)]  # noqa: E731
        self.assertIsNone(checks.plan_progress([]))
        self.assertEqual(checks.plan_progress(steps(False, False, False, False)), 5)
        self.assertEqual(checks.plan_progress(steps(True, True, False, False)), 45)
        self.assertEqual(checks.plan_progress(steps(True, True, False, False), has_pr=True), 50)
        self.assertEqual(checks.plan_progress(steps(True, True, True, True), has_pr=True), 95)  # 100 only when the goal is marked done


class ReadAndGrepTests(unittest.IsolatedAsyncioTestCase):
    async def _read(self, text, **kw):
        import base64
        data = {"encoding": "base64", "content": base64.b64encode(text.encode()).decode()}
        with patch.object(github, "_get", AsyncMock(return_value=(data, None))):
            return await github.read("bot/a.py", **kw)

    async def test_line_range_is_numbered_and_capped(self):
        text = "\n".join(f"line{i}" for i in range(1, 1001))
        out = await self._read(text, start=10, end=12)
        self.assertEqual(out["lines"], "10-12 из 1000")
        self.assertTrue(out["content"].startswith("10: line10\n11: line11"))
        wide = await self._read(text, start=1, end=1000)
        self.assertEqual(wide["lines"], "1-400 из 1000")
        self.assertIn("error", await self._read("a\nb", start=50))

    async def test_big_file_gets_a_hint(self):
        out = await self._read("x" * 30_000)
        self.assertTrue(out["truncated"])
        self.assertIn("start/end", out["hint"])

    async def test_missing_path_error_is_explained(self):
        with patch.object(github, "_get", AsyncMock(return_value=(None, "HTTP 404"))):
            self.assertIn("такого пути нет", (await github.read("bot/nope.py"))["error"])

    def test_grep_regex_prefix_and_limits(self):
        files = {"bot/a.py": "def Foo():\n    pass\nfoo()\nFOO()\nfoo()\nfoo()\nfoo()", "site/b.ts": "foo", "bot/c.py": "nothing"}
        out = github.grep_files(files, "foo", "")
        self.assertEqual({h["path"] for h in out["hits"]}, {"bot/a.py", "site/b.ts"})
        self.assertLessEqual(len([h for h in out["hits"] if h["path"] == "bot/a.py"]), 4)  # at most 4 hits per file
        self.assertEqual([h["path"] for h in github.grep_files(files, "foo", "site/")["hits"]], ["site/b.ts"])
        self.assertIn("hint", github.grep_files(files, "zzz"))
        self.assertIn("hits", github.grep_files(files, "def ("))  # invalid regex falls back to plain text, no crash
        self.assertIn("error", github.grep_files(files, " "))

    async def test_read_capped_collects_every_chunk(self):
        # regression: StreamReader.read(n) returned only the first 8 KB chunk, so the repo zip never parsed on the live bot
        class Stream:
            def __init__(self, chunks):
                self.chunks = chunks

            async def iter_chunked(self, size):
                for c in self.chunks:
                    yield c

        resp = SimpleNamespace(content=Stream([b"a" * 10, b"b" * 10, b"c" * 10]))
        self.assertEqual(await github.read_capped(resp, 100), (b"a" * 10 + b"b" * 10 + b"c" * 10, False))
        body, cut = await github.read_capped(SimpleNamespace(content=Stream([b"a" * 10, b"b" * 10])), 15)
        self.assertEqual((len(body), cut), (15, True))

    def test_parse_zip_keeps_only_source_text(self):
        import io
        import zipfile
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            z.writestr("repo-abc/bot/a.py", "print(1)")
            z.writestr("repo-abc/bot/pic.png", b"\x89PNG")
            z.writestr("repo-abc/node_modules/x.js", "x")
            z.writestr("repo-abc/site/big.ts", "x" * 300_000)
            z.writestr("repo-abc/site/package-lock.json", "{}")
            z.writestr("repo-abc/secret/readme.md", "outside the allowed folders")
            z.writestr("repo-abc/docs/notes.md", "ok")
        files = github.parse_zip(buf.getvalue())
        self.assertEqual(sorted(files), ["bot/a.py", "docs/notes.md"])
        self.assertEqual(github.parse_zip(b"not a zip"), {})

    async def test_ci_details_attaches_the_failure_log(self):
        ci = {"total": 2, "passed": 1, "failed": 1, "pending": 0, "failing": ["bot"], "failing_ids": [77], "health_pct": 50}
        with patch.object(github, "ci", AsyncMock(return_value=ci)), patch.object(github, "job_log", AsyncMock(return_value=UNITTEST_LOG)):
            out = await github.ci_details("sha")
        self.assertIn("ValueError: bad id 0", out["failure_log"])
        with patch.object(github, "ci", AsyncMock(return_value=ci)), patch.object(github, "job_log", AsyncMock(return_value=None)):
            self.assertIn("недоступен", (await github.ci_details("sha"))["failure_log"])
        green = {"total": 1, "passed": 1, "failed": 0, "pending": 0, "health_pct": 100}
        with patch.object(github, "ci", AsyncMock(return_value=green)):
            self.assertNotIn("failure_log", await github.ci_details("sha"))

    def test_failing_ids_are_collected(self):
        s = github.summarize_checks([{"status": "completed", "conclusion": "failure", "name": "bot", "id": 5}])
        self.assertEqual(s["failing_ids"], [5])


class PlanToolsTests(unittest.IsolatedAsyncioTestCase):
    async def test_step_done_recomputes_progress(self):
        ctx = tools.Ctx(bot=None, goal={"id": 1, "tasks": [{"t": "a", "done": False}, {"t": "b", "done": False}], "pr_number": None})
        save = AsyncMock(return_value=RPCResult(data={}))
        with patch.object(tools.rpc, "bot_agent_goal_save", save):
            out = json.loads(await tools.run_tool(ctx, "step_done", {"n": 1}))
            self.assertEqual(out["progress_pct"], 45)
            self.assertEqual(ctx.steps_marked, 1)
            out = json.loads(await tools.run_tool(ctx, "step_done", {}))  # no n: the first open step
            self.assertEqual(out["progress_pct"], 90)
            self.assertIn("note", json.loads(await tools.run_tool(ctx, "step_done", {})))
        self.assertTrue(all(t["done"] for t in ctx.goal["tasks"]))

    async def test_step_done_without_plan_or_goal(self):
        self.assertIn("error", json.loads(await tools.run_tool(tools.Ctx(bot=None), "step_done", {})))
        self.assertIn("error", json.loads(await tools.run_tool(tools.Ctx(bot=None, goal={"id": 1, "tasks": []}), "step_done", {})))

    async def test_goal_update_overrides_guessed_progress_when_a_plan_exists(self):
        ctx = tools.Ctx(bot=None, goal={"id": 1, "tasks": [{"t": "a", "done": True}, {"t": "b", "done": False}]})
        save = AsyncMock(return_value=RPCResult(data={"progress_pct": 50}))
        with patch.object(tools.rpc, "bot_agent_goal_save", save):
            await tools.run_tool(ctx, "goal_update", {"progress_pct": 99})
            self.assertEqual(save.await_args.args[1]["progress_pct"], 45)
            await tools.run_tool(ctx, "goal_update", {"status": "done"})
            self.assertEqual(save.await_args.args[1]["progress_pct"], 100)
            await tools.run_tool(ctx, "goal_update", {"tasks": ["один", "два", "три"]})  # new plan given as plain strings
            self.assertEqual(len(save.await_args.args[1]["tasks"]), 3)

    async def test_goal_new_stores_the_plan(self):
        save = AsyncMock(return_value=RPCResult(data={"id": 4}))
        with patch.object(tools.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[]))), patch.object(tools.rpc, "bot_agent_goal_save", save):
            out = json.loads(await tools.run_tool(tools.Ctx(bot=None), "goal_new", {"title": "Новая цель", "expected": "x", "tasks": ["а", "б"]}))
        self.assertTrue(out["ok"])
        self.assertEqual(save.await_args.args[1]["progress_pct"], 5)
        self.assertEqual(save.await_args.args[1]["tasks"][0], {"t": "а", "done": False})

    async def test_commit_with_broken_python_is_refused_before_github(self):
        ctx = tools.Ctx(bot=None, goal={"id": 1, "title": "T", "branch": "agent/t-1"})
        push = AsyncMock(return_value=("abc", None))
        with patch.object(tools, "_day_counter", AsyncMock(return_value=0)), patch.object(github, "commit_files", push):
            out = json.loads(await tools.run_tool(ctx, "commit", {"message": "m", "files": [{"path": "bot/a.py", "content": "def (:"}]}))
        self.assertIn("коммит НЕ сделан", out["error"])
        push.assert_not_awaited()

    async def test_tool_schemas(self):
        names = {t["function"]["name"] for t in tools.SCHEMAS}
        self.assertIn("step_done", names)
        self.assertIn("step_done", {t["function"]["name"] for t in tools.wrapup_schemas()})
        self.assertNotIn("step_done", {t["function"]["name"] for t in tools.idea_schemas()})
        props = next(t for t in tools.SCHEMAS if t["function"]["name"] == "repo_read")["function"]["parameters"]["properties"]
        self.assertIn("start", props)
        self.assertIn("end", props)


class JobsTests(unittest.IsolatedAsyncioTestCase):
    def test_titles(self):
        self.assertEqual(jobs.make_title("  "), "Задача от админа")
        self.assertLessEqual(len(jobs.make_title("слово " * 40)), 82)
        self.assertEqual(jobs.make_title("Добавить кнопку"), "Добавить кнопку")

    async def test_add_task_queues_as_paused_admin_goal(self):
        save = AsyncMock(return_value=RPCResult(data={"id": 8, "title": "x"}))
        with patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[]))), \
                patch.object(jobs.rpc, "bot_agent_goal_save", save), patch.object(jobs.rpc, "bot_agent_journal_add", AsyncMock()):
            goal, note = await jobs.add_task("Добавить в меню кнопку правил", "@adm")
        self.assertEqual(note, "")
        patch_sent = save.await_args.args[1]
        self.assertEqual((patch_sent["source"], patch_sent["status"]), ("admin", "paused"))
        self.assertIn("@adm", patch_sent["why"])

    async def test_add_task_refuses_short_duplicate_and_full_queue(self):
        existing = [{"id": 1, "source": "admin", "title": "Добавить кнопку правил в меню", "expected": "Добавить кнопку правил в меню"}]
        with patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=existing))):
            self.assertIsNone((await jobs.add_task("ок", "@a"))[0])
            goal, note = await jobs.add_task("добавить кнопку правил в меню", "@a")
            self.assertEqual(goal["id"], 1)
            self.assertIn("уже в очереди", note)
        full = [{"id": i, "source": "admin", "title": f"Задача номер {i}"} for i in range(jobs.MAX_QUEUED)]
        with patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=full))):
            goal, note = await jobs.add_task("совсем другая новая просьба админа", "@a")
        self.assertIsNone(goal)
        self.assertIn("уже 10", note)

    async def test_queue_ignores_the_agents_own_paused_goals(self):
        rows = [{"id": 2, "source": "admin"}, {"id": 1, "source": "agent"}, {"id": 3, "source": "admin"}]
        with patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=rows))):
            self.assertEqual([g["id"] for g in await jobs.queued()], [2, 3])

    async def test_idea_to_work_forgets_the_idea(self):
        forget = AsyncMock(return_value=RPCResult(data=True))
        with patch.object(jobs.rpc, "bot_agent_mem_list", AsyncMock(return_value=RPCResult(data=[{"id": 5, "body": "Показывать онлайн игроков в меню", "importance": 3}]))), \
                patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[]))), \
                patch.object(jobs.rpc, "bot_agent_goal_save", AsyncMock(return_value=RPCResult(data={"id": 9, "title": "t"}))), \
                patch.object(jobs.rpc, "bot_agent_journal_add", AsyncMock()), patch.object(jobs.rpc, "bot_agent_mem_forget", forget):
            goal, note = await jobs.take_idea(5, "@adm")
            self.assertEqual(goal["id"], 9)
            forget.assert_awaited_once_with(5)
            self.assertEqual((await jobs.take_idea(77, "@adm"))[0], None)  # unknown idea: nothing is queued

    async def test_wake_clears_the_cycle_timer(self):
        patch_state = AsyncMock(return_value=RPCResult(data={}))
        with patch.object(jobs.rpc, "bot_agent_state_patch", patch_state):
            await jobs.wake()
        patch_state.assert_awaited_once_with({"last_cycle": None})


class ChatTests(unittest.IsolatedAsyncioTestCase):
    def test_parse_json_and_plain_text(self):
        self.assertEqual(chat.parse('{"reply": "Делаю X", "task": ""}'), ("Делаю X", ""))
        self.assertEqual(chat.parse('текст до {"reply": "ок", "task": "Добавить Y"} после'), ("ок", "Добавить Y"))
        self.assertEqual(chat.parse("просто ответ"), ("просто ответ", ""))
        self.assertEqual(chat.parse("{плохой json"), ("", ""))

    async def _answer(self, content, staff):
        with patch.object(chat.client, "is_configured", lambda role="user": True), \
                patch.object(chat.client, "chat", AsyncMock(return_value={"content": content})), \
                patch.object(chat, "status_text", AsyncMock(return_value="Работа: идёт")):
            return await chat.answer("добавь кнопку", "@a", staff)

    async def test_only_staff_can_create_tasks_by_talking(self):
        raw = '{"reply": "Записал", "task": "Добавить кнопку"}'
        self.assertEqual(await self._answer(raw, True), ("Записал", "Добавить кнопку"))
        self.assertEqual(await self._answer(raw, False), ("Записал", ""))

    async def test_ai_down_returns_none(self):
        with patch.object(chat.client, "is_configured", lambda role="user": True), \
                patch.object(chat.client, "chat", AsyncMock(side_effect=chat.client.AIError("down"))):
            self.assertIsNone(await chat.answer("что делаешь?", "@a", True))
        with patch.object(chat.client, "is_configured", lambda role="user": False):
            self.assertIsNone(await chat.answer("что делаешь?", "@a", True))


def _goals_by_status(**by_status):
    async def goals(status=None, limit=20):
        return RPCResult(data=by_status.get(status, []))
    return goals


class ChooseWorkTests(unittest.IsolatedAsyncioTestCase):
    async def _choose(self, state=None, **by_status):
        save = AsyncMock(side_effect=lambda gid, patch_: RPCResult(data={"id": gid, "head_sha": "abc", **patch_}))
        with patch.object(brain.rpc, "bot_agent_goals_list", _goals_by_status(**by_status)), patch.object(brain.rpc, "bot_agent_goal_save", save), \
                patch.object(brain.rpc, "bot_agent_mem_add", AsyncMock()), patch.object(brain.rpc, "bot_agent_state_patch", AsyncMock()), \
                patch.object(github, "ci_details", AsyncMock(return_value={"failed": 1, "pending": 0, "failing": ["bot"], "failure_log": "ValueError: boom"})):
            return await brain._choose_work(state or {}), save

    async def test_active_goal_continues(self):
        (goal, hint, idea), _ = await self._choose(active=[{"id": 1, "title": "A", "source": "agent", "pr_number": 3, "progress_pct": 60}])
        self.assertEqual((goal["id"], idea), (1, False))

    async def test_admin_task_is_taken_when_idle(self):
        (goal, hint, idea), save = await self._choose(paused=[{"id": 7, "source": "admin", "title": "Задача админа", "expected": "сделай X"}])
        self.assertEqual(goal["id"], 7)
        self.assertIn("ЗАДАЧА ОТ АДМИНА", hint)
        self.assertEqual(save.await_args.args[1], {"status": "active"})

    async def test_admin_task_preempts_a_barely_started_own_idea(self):
        own = {"id": 1, "title": "Своя идея", "source": "agent", "pr_number": None, "progress_pct": 10, "expected": "e"}
        (goal, _, _), save = await self._choose(active=[own], paused=[{"id": 7, "source": "admin", "title": "T", "expected": "e"}])
        self.assertEqual(goal["id"], 7)
        self.assertEqual(save.await_args_list[0].args, (1, {"status": "dropped"}))

    async def test_admin_task_waits_when_own_goal_is_underway(self):
        own = {"id": 1, "title": "Своя", "source": "agent", "pr_number": 5, "progress_pct": 70}
        (goal, _, _), _ = await self._choose(active=[own], paused=[{"id": 7, "source": "admin", "title": "T", "expected": "e"}])
        self.assertEqual(goal["id"], 1)

    async def test_red_pr_is_fixed_first_with_the_log_and_limited_attempts(self):
        red = {"id": 3, "pr_number": 11, "head_sha": "abc", "merged_at": None, "review": {"ci": {"failed": 1, "pending": 0}}}
        (goal, hint, idea), save = await self._choose(done=[red])
        self.assertEqual(goal["id"], 3)
        self.assertIn("ValueError: boom", hint)
        self.assertIn("попытка 1 из 3", hint)
        self.assertFalse(idea)
        (goal, _, _), _ = await self._choose(state={"reworks": {"11": 3}}, done=[red])
        self.assertIsNone(goal)  # three attempts used: leave it to the humans

    async def test_pending_checks_are_not_reworked(self):
        waiting = {"id": 3, "pr_number": 11, "head_sha": "abc", "review": {"ci": {"failed": 0, "pending": 2}}}
        (goal, _, idea), _ = await self._choose(done=[waiting])
        self.assertIsNone(goal)
        self.assertFalse(idea)

    async def test_full_queue_means_idea_mode(self):
        done = [{"id": i, "pr_number": 100 + i, "head_sha": "x", "review": {"verdict": "OK", "ci": {"failed": 0, "pending": 0}}} for i in range(config.MAX_WAITING)]
        (goal, _, idea), _ = await self._choose(done=done)
        self.assertIsNone(goal)
        self.assertTrue(idea)


class NotifyReadyTests(unittest.IsolatedAsyncioTestCase):
    GOAL = {"id": 1, "pr_number": 20, "health_pct": 100, "review": {"plain": "Теперь лучше", "verdict": "OK"}, "title": "T", "expected": "e", "branch": "agent/t"}

    async def _run(self, state, goals):
        patch_state = AsyncMock(return_value=RPCResult(data={}))
        post = AsyncMock(return_value=SimpleNamespace(message_id=1))
        with patch.object(brain.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data=state))), patch.object(brain.rpc, "bot_agent_state_patch", patch_state), \
                patch.object(brain.report, "waiting_goals", AsyncMock(return_value=goals)), patch.object(brain.report, "post", post), \
                patch.object(brain.report, "detail", AsyncMock(return_value=("card", None))):
            await brain._notify_ready(None)
        return patch_state, post

    async def test_first_run_only_remembers_what_is_already_waiting(self):
        patch_state, post = await self._run({}, [self.GOAL])
        post.assert_not_awaited()
        patch_state.assert_awaited_once_with({"notified_prs": [20]})

    async def test_new_green_task_is_announced_once(self):
        patch_state, post = await self._run({"notified_prs": [5]}, [self.GOAL])
        post.assert_awaited_once()
        self.assertEqual(patch_state.await_args.args[0], {"notified_prs": [5, 20]})
        patch_state, post = await self._run({"notified_prs": [5, 20]}, [self.GOAL])
        post.assert_not_awaited()

    async def test_red_or_unreviewed_tasks_wait_silently(self):
        for goal in ({**self.GOAL, "health_pct": 60}, {**self.GOAL, "review": {}}):
            _, post = await self._run({"notified_prs": []}, [goal])
            post.assert_not_awaited()


class InterfaceTests(unittest.IsolatedAsyncioTestCase):
    async def test_panel_buttons(self):
        rows = report.panel().inline_keyboard
        self.assertEqual([b.callback_data for r in rows for b in r], ["agent:list", "agent:ideas", "agent:toggle", "agent:help"])
        self.assertEqual(report.panel(paused=True).inline_keyboard[1][0].text, "▶ Продолжить")
        self.assertEqual(report.panel(refresh=True).inline_keyboard[0][0].text, "🔄 Обновить")

    def test_live_text_shows_the_plan(self):
        ctx = tools.Ctx(bot=None, goal={"title": "Цель", "progress_pct": 45, "tasks": [{"t": "Найти место", "done": True}, {"t": "Внести правку", "done": False}, {"t": "Проверить", "done": False}]})
        ctx.step = 3
        text = report.live_text(ctx, 24)
        self.assertIn("✅ Найти место", text)
        self.assertIn("▶ Внести правку", text)
        self.assertIn("▫ Проверить", text)

    def test_red_checks_are_explained(self):
        line = report._status_line({"health_pct": 60, "review": {"ci": {"failed": 1, "pending": 0}}})
        self.assertIn("не прошли", line)
        self.assertIn("идут", report._status_line({"health_pct": 60, "review": {"ci": {"failed": 0, "pending": 1}}}))

    async def test_build_shows_admin_queue_and_panel(self):
        queue = [{"id": 7, "source": "admin", "title": "Кнопка правил"}]
        with patch.object(report.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={}))), \
                patch.object(report.rpc, "bot_agent_goals_list", _goals_by_status(paused=queue)):
            text, markup = await report.build()
        self.assertIn("Ваши задачи", text)
        self.assertIn("Кнопка правил", text)
        data = [b.callback_data for r in markup.inline_keyboard for b in r]
        self.assertEqual(data, ["agent:list", "agent:ideas", "agent:toggle", "agent:help"])

    async def test_ideas_view(self):
        with patch.object(report.jobs.rpc, "bot_agent_mem_list", AsyncMock(return_value=RPCResult(data=[{"id": 4, "body": "Идея про онлайн", "importance": 3}, {"id": 9, "body": "Другая идея", "importance": 2}]))):
            text, markup = await report.ideas_view()
        self.assertIn("1. Идея про онлайн", text)
        data = [b.callback_data for r in markup.inline_keyboard for b in r]
        self.assertEqual(data[:4], ["agent:idea:4", "agent:idea:9", "agent:noidea:4", "agent:noidea:9"])
        with patch.object(report.jobs.rpc, "bot_agent_mem_list", AsyncMock(return_value=RPCResult(data=[]))):
            text, _ = await report.ideas_view()
        self.assertIn("/task", text)

    async def test_detail_header(self):
        goal = {"id": 1, "title": "T", "pr_number": 5, "progress_pct": 100, "health_pct": 100, "expected": "e", "review": {"verdict": "OK", "plain": "Лучше"}, "branch": "agent/a"}
        with patch.object(report.rpc, "bot_agent_goals_list", _goals_by_status(done=[goal])), patch.object(github, "preview_url", AsyncMock(return_value=None)), \
                patch.object(github, "_repo", lambda: ("o/r", None)):
            text, _ = await report.detail(5, header="🔔 <b>Готова новая задача</b>")
        self.assertTrue(text.startswith("🔔"))
        self.assertIn("№1", text)

    def test_help_mentions_all_commands(self):
        for word in ("/task", "/ideas", "/agent", "Очередь", "Принять"):
            self.assertIn(word, report.HELP)


class TopicHandlerTests(unittest.IsolatedAsyncioTestCase):
    def _message(self, text, user_id=1):
        reply = AsyncMock()
        return SimpleNamespace(text=text, message_id=10, reply=reply, reply_to_message=None, message_thread_id=config.THREAD_ID,
                               from_user=SimpleNamespace(id=user_id, username="adm", full_name="Adm"),
                               bot=SimpleNamespace(me=AsyncMock(return_value=SimpleNamespace(id=99, username="prisma_bot")))), reply

    async def test_task_command_queues_and_wakes(self):
        from handlers import agent_topic
        message, reply = self._message("/task Добавить в меню кнопку правил")
        wake = AsyncMock()
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True})), \
                patch.object(agent_topic.jobs, "add_task", AsyncMock(return_value=({"id": 7, "title": "Добавить в меню кнопку правил"}, ""))), \
                patch.object(agent_topic.jobs, "queued", AsyncMock(return_value=[{"id": 7}])), patch.object(agent_topic.jobs, "wake", wake), \
                patch.object(agent_topic.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[]))):
            await agent_topic.admin_commands(message)
        wake.assert_awaited_once()
        self.assertIn("Принял задачу", reply.await_args.args[0])

    async def test_task_command_needs_text_and_staff(self):
        from handlers import agent_topic
        message, reply = self._message("/task")
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True})):
            await agent_topic.admin_commands(message)
        self.assertIn("Напишите задачу", reply.await_args.args[0])
        message, reply = self._message("/task сделай что-нибудь")
        add = AsyncMock()
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": False})), patch.object(agent_topic.jobs, "add_task", add):
            await agent_topic.admin_commands(message)
        add.assert_not_awaited()

    async def test_question_to_the_agent_gets_an_answer_and_can_queue_a_task(self):
        from handlers import agent_topic
        agent_topic._last_ack.clear()
        message, reply = self._message("@prisma_bot добавь кнопку правил в меню")
        wake = AsyncMock()
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True})), \
                patch.object(agent_topic.rpc, "bot_agent_inbox_add", AsyncMock()), patch.object(agent_topic.rpc, "bot_agent_mem_add", AsyncMock()), \
                patch.object(agent_topic.chat, "answer", AsyncMock(return_value=("Записал, сделаю", "Добавить кнопку правил"))), \
                patch.object(agent_topic.jobs, "add_task", AsyncMock(return_value=({"id": 7, "title": "Добавить кнопку правил"}, ""))), patch.object(agent_topic.jobs, "wake", wake):
            await agent_topic.ingest(message)
        self.assertIn("Записал, сделаю", reply.await_args.args[0])
        self.assertIn("Поставил задачу", reply.await_args.args[0])
        wake.assert_awaited_once()

    async def test_ai_down_falls_back_to_the_old_acknowledgement(self):
        from handlers import agent_topic
        agent_topic._last_ack.clear()
        message, reply = self._message("@prisma_bot привет")
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": False})), \
                patch.object(agent_topic.rpc, "bot_agent_inbox_add", AsyncMock()), patch.object(agent_topic.chat, "answer", AsyncMock(return_value=None)):
            await agent_topic.ingest(message)
        self.assertIn("Принял", reply.await_args.args[0])

    async def test_unaddressed_message_is_only_stored(self):
        from handlers import agent_topic
        agent_topic._last_ack.clear()
        message, reply = self._message("просто разговор без обращения к боту")
        add = AsyncMock()
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True})), patch.object(agent_topic.rpc, "bot_agent_inbox_add", add), \
                patch.object(agent_topic.rpc, "bot_agent_mem_add", AsyncMock()):
            await agent_topic.ingest(message)
        add.assert_awaited_once()
        reply.assert_not_awaited()


if __name__ == "__main__":
    unittest.main()
