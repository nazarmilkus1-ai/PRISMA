import os
import time
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")

from db.rpc import RPCResult
from services.agent import autopilot, brain, config, github, jobs, merge, report

GREEN = {"total": 3, "passed": 3, "failed": 0, "pending": 0, "failing": []}
TODAY = time.strftime("%Y-%m-%d")


def _info(number=7, **kw):
    base = {"number": number, "state": "open", "merged": False, "title": "t", "head_ref": "agent/x-0101-0000", "head_sha": "abc",
            "paths": ["bot/handlers/menu.py"], "mergeable": True}
    base.update(kw)
    return base


def _goal(number=7, **kw):
    base = {"id": number, "pr_number": number, "title": f"Задача {number}", "expected": "что-то улучшить", "merged_at": None,
            "review": {"verdict": "OK", "plain": "Стало лучше", "ci": {"total": 3, "failed": 0, "pending": 0}}}
    base.update(kw)
    return base


class SwitchTests(unittest.TestCase):
    def test_default_is_on_and_state_overrides(self):
        with patch.object(config, "AUTO_MERGE", True):
            self.assertTrue(config.auto_merge_on({}))
            self.assertFalse(config.auto_merge_on({"auto_merge": False}))
        with patch.object(config, "AUTO_MERGE", False):
            self.assertFalse(autopilot.enabled({}))
            self.assertTrue(autopilot.enabled({"auto_merge": True}))

    def test_cycle_cadence(self):
        with patch.object(config, "AUTO_MERGE", True):
            self.assertEqual(autopilot.cycle_seconds({}, []), config.BUSY_CYCLE_SECONDS)  # autonomous: never waits for the slow timer
            self.assertEqual(autopilot.cycle_seconds({"paused": True}, []), config.CYCLE_SECONDS)
            self.assertEqual(autopilot.cycle_seconds({"auto_merge": False}, []), config.CYCLE_SECONDS)
            self.assertEqual(autopilot.cycle_seconds({"auto_merge": False}, [{"status": "active"}]), config.BUSY_CYCLE_SECONDS)
            queued = [{"status": "paused", "source": "redo"}]
            self.assertEqual(autopilot.cycle_seconds({"auto_merge": False}, queued), config.BUSY_CYCLE_SECONDS)
            self.assertEqual(autopilot.cycle_seconds({"auto_merge": False}, [{"status": "paused", "source": "agent"}]), config.CYCLE_SECONDS)


class StepTests(unittest.IsolatedAsyncioTestCase):
    async def _step(self, goals, infos, state=None, ci=GREEN, update_err=None, merged=None):
        """Run one autopilot pass with every outside world call mocked; returns the mocks."""
        state = {"auto_merge": True, **(state or {})}
        mocks = SimpleNamespace(
            merge_pr=AsyncMock(return_value=merged or {"ok": True, "message": "merged", "sha": "m1"}),
            update_branch=AsyncMock(return_value=update_err), close_pr=AsyncMock(return_value=None),
            post=AsyncMock(return_value=SimpleNamespace(message_id=1)), save=AsyncMock(return_value=RPCResult(data={})),
            patch=AsyncMock(return_value=RPCResult(data={})), add_task=AsyncMock(return_value=({"id": 99}, "")))

        async def goals_list(status=None, limit=20):
            return RPCResult(data=goals)

        async def pr_info(number):
            return infos.get(number, {"error": "missing"})

        with patch.object(autopilot.rpc, "bot_agent_goals_list", goals_list), patch.object(merge.rpc, "bot_agent_goals_list", goals_list), \
                patch.object(github, "pr_info", pr_info), patch.object(github, "ci", AsyncMock(return_value=ci)), \
                patch.object(github, "merge_pr", mocks.merge_pr), patch.object(github, "update_branch", mocks.update_branch), \
                patch.object(github, "close_pr", mocks.close_pr), patch.object(autopilot.report, "post", mocks.post), \
                patch.object(autopilot.rpc, "bot_agent_goal_save", mocks.save), patch.object(merge.rpc, "bot_agent_goal_save", mocks.save), \
                patch.object(autopilot.rpc, "bot_agent_state_patch", mocks.patch), patch.object(autopilot.rpc, "bot_agent_mem_add", AsyncMock()), \
                patch.object(merge.rpc, "bot_agent_mem_add", AsyncMock()), patch.object(merge.rpc, "bot_agent_journal_add", AsyncMock()), \
                patch.object(autopilot.rpc, "bot_agent_journal_add", AsyncMock()), patch.object(autopilot.jobs, "add_task", mocks.add_task):
            await autopilot.step(None, state)
        return mocks

    async def test_ready_pr_is_merged_by_the_agent_and_announced_with_a_revert_button(self):
        m = await self._step([_goal(7)], {7: _info(7)})
        m.merge_pr.assert_awaited_once()
        state_patch = m.patch.await_args.args[0]
        self.assertEqual(state_patch["auto_merges"], {"day": TODAY, "n": 1})
        self.assertGreater(state_patch["last_auto_merge"], time.time() - 5)
        text, markup = m.post.await_args.args[1], m.post.await_args.args[2]
        self.assertIn("сам", text)
        self.assertEqual(markup.inline_keyboard[0][0].callback_data, "agent:revert:7")
        saved = [c.args[1] for c in m.save.await_args_list if "merged" in c.args[1]]
        self.assertEqual(saved[0]["review"]["merge_sha"], "m1")  # the «Откатить» button needs it

    async def test_only_one_merge_per_pass_oldest_first(self):
        m = await self._step([_goal(9), _goal(7)], {7: _info(7), 9: _info(9)})
        self.assertEqual(m.merge_pr.await_count, 1)
        self.assertEqual(m.merge_pr.await_args.args[0], 7)

    async def test_gap_and_daily_cap_hold_merges_back(self):
        m = await self._step([_goal(7)], {7: _info(7)}, state={"last_auto_merge": time.time() - 60})
        m.merge_pr.assert_not_awaited()
        m = await self._step([_goal(7)], {7: _info(7)}, state={"auto_merges": {"day": TODAY, "n": config.MAX_AUTO_MERGES_PER_DAY}})
        m.merge_pr.assert_not_awaited()
        m = await self._step([_goal(7)], {7: _info(7)}, state={"auto_merges": {"day": "2000-01-01", "n": 999}})
        m.merge_pr.assert_awaited_once()  # yesterday's counter does not count

    async def test_own_code_and_migrations_are_left_to_the_human(self):
        for path, kind in (("bot/services/agent/brain.py", "self"), ("supabase/migrations/2026_x.sql", "migrations")):
            m = await self._step([_goal(7)], {7: _info(7, paths=[path])})
            m.merge_pr.assert_not_awaited()
            self.assertEqual(m.save.await_args.args[1]["review"]["manual"], kind)

    async def test_reviewer_block_and_unfinished_ci_are_not_merged(self):
        blocked = _goal(7, review={"verdict": "BLOCK", "ci": {"total": 3}})
        m = await self._step([blocked], {7: _info(7)})
        m.merge_pr.assert_not_awaited()
        for ci in ({**GREEN, "total": 0, "passed": 0}, {**GREEN, "pending": 1}, {**GREEN, "failed": 1, "passed": 2}):
            m = await self._step([_goal(7)], {7: _info(7)}, ci=ci)
            m.merge_pr.assert_not_awaited()

    async def test_switched_off_does_nothing(self):
        m = await self._step([_goal(7)], {7: _info(7)}, state={"auto_merge": False})
        m.merge_pr.assert_not_awaited()
        m.post.assert_not_awaited()

    async def test_failed_github_merge_is_not_announced(self):
        m = await self._step([_goal(7)], {7: _info(7)}, merged={"ok": False, "message": "HTTP 405", "sha": None})
        m.post.assert_not_awaited()
        m.patch.assert_not_awaited()

    async def test_conflicting_pr_gets_its_branch_updated_not_merged(self):
        m = await self._step([_goal(7)], {7: _info(7, mergeable=False)})
        m.update_branch.assert_awaited_once_with(7, "abc")
        m.merge_pr.assert_not_awaited()
        m.close_pr.assert_not_awaited()

    async def test_real_conflict_closes_the_pr_and_queues_a_rebuild(self):
        info = _info(7, mergeable=False)
        m = await self._step([_goal(7)], {7: info}, update_err="HTTP 422")
        m.close_pr.assert_awaited_once_with(7)
        task = m.add_task.await_args
        self.assertEqual(task.kwargs["source"], "redo")
        self.assertTrue(task.kwargs["title"].startswith("Переделать: "))
        self.assertIn("Задача 7", task.args[0])
        dropped = [c.args for c in m.save.await_args_list if c.args[1].get("status") == "dropped"]
        self.assertEqual(dropped, [(7, {"status": "dropped"})])

    async def test_a_conflict_that_resolved_itself_is_not_rebuilt(self):
        async def moved(number):
            return _info(7, mergeable=False, head_sha="newer")  # the branch moved between the first read and the failed update

        with patch.object(github, "pr_info", moved), patch.object(github, "update_branch", AsyncMock(return_value="HTTP 422")), \
                patch.object(github, "close_pr", AsyncMock()) as close:
            await autopilot._unblock(_goal(7), _info(7, mergeable=False), {})
        close.assert_not_awaited()

    async def test_unrelated_pr_error_is_skipped_quietly(self):
        m = await self._step([_goal(7)], {7: {"error": "GitHub HTTP 500"}})
        m.merge_pr.assert_not_awaited()


class RedoTests(unittest.IsolatedAsyncioTestCase):
    async def _redo(self, goal, state):
        close, save, patch_state = AsyncMock(), AsyncMock(return_value=RPCResult(data={})), AsyncMock()
        mem, journal = AsyncMock(), AsyncMock()
        add = AsyncMock(return_value=({"id": 50}, ""))
        with patch.object(github, "close_pr", close), patch.object(autopilot.rpc, "bot_agent_goal_save", save), \
                patch.object(autopilot.rpc, "bot_agent_state_patch", patch_state), patch.object(autopilot.rpc, "bot_agent_mem_add", mem), \
                patch.object(autopilot.rpc, "bot_agent_journal_add", journal), patch.object(autopilot.jobs, "add_task", add):
            out = await autopilot.redo(goal, "конфликт", state)
        return out, SimpleNamespace(close=close, save=save, state=patch_state, mem=mem, add=add)

    async def test_first_redo_closes_drops_and_queues(self):
        out, m = await self._redo(_goal(7), {})
        self.assertTrue(out)
        m.close.assert_awaited_once_with(7)
        m.save.assert_awaited_once_with(7, {"status": "dropped"})
        self.assertEqual(m.state.await_args.args[0], {"redos": {"задача 7": 1}})
        self.assertEqual(m.add.await_args.kwargs["title"], "Переделать: Задача 7")
        m.mem.assert_not_awaited()

    async def test_a_rebuilt_task_keeps_counting_under_its_original_name(self):
        out, m = await self._redo(_goal(8, title="Переделать: Переделать: Задача 7"), {"redos": {"задача 7": 1}})
        self.assertTrue(out)
        self.assertEqual(m.state.await_args.args[0], {"redos": {"задача 7": 2}})
        self.assertEqual(m.add.await_args.kwargs["title"], "Переделать: Задача 7")  # prefixes never pile up

    async def test_after_max_redos_the_task_is_given_up_with_a_lesson(self):
        out, m = await self._redo(_goal(7), {"redos": {"задача 7": autopilot.MAX_REDOS}})
        self.assertFalse(out)
        m.close.assert_awaited_once_with(7)
        m.add.assert_not_awaited()
        self.assertEqual(m.mem.await_args.args[0], "lesson")


class QueueTests(unittest.IsolatedAsyncioTestCase):
    async def test_redo_tasks_queue_behind_admin_tasks(self):
        rows = [{"id": 1, "source": "redo"}, {"id": 5, "source": "admin"}, {"id": 2, "source": "agent"}, {"id": 3, "source": "admin"}]
        with patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=rows))):
            self.assertEqual([g["id"] for g in await jobs.queued()], [3, 5, 1])

    async def test_redo_task_is_saved_with_its_own_source_and_title(self):
        save = AsyncMock(return_value=RPCResult(data={"id": 8}))
        with patch.object(jobs.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[]))), \
                patch.object(jobs.rpc, "bot_agent_goal_save", save), patch.object(jobs.rpc, "bot_agent_journal_add", AsyncMock()):
            goal, note = await jobs.add_task("Переделай заново: добавить кнопку правил", "агент", source="redo", title="Переделать: Кнопка правил")
        self.assertEqual(note, "")
        sent = save.await_args.args[1]
        self.assertEqual((sent["source"], sent["status"], sent["title"]), ("redo", "paused", "Переделать: Кнопка правил"))


class MergeGateAutonomyTests(unittest.IsolatedAsyncioTestCase):
    async def _eval(self, info, ci=GREEN):
        with patch.object(github, "pr_info", AsyncMock(return_value=info)), patch.object(github, "ci", AsyncMock(return_value=ci)), \
                patch.object(merge.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=[{"pr_number": 7, "review": {}}]))):
            return await merge.evaluate(7, owner=False)

    async def test_conflict_and_not_started_checks_get_plain_refusals(self):
        ok, text, _ = await self._eval(_info(mergeable=False))
        self.assertFalse(ok)
        self.assertIn("Конфликт", text)
        ok, text, _ = await self._eval(_info(), ci={**GREEN, "total": 0, "passed": 0})
        self.assertFalse(ok)
        self.assertIn("ещё не запустились", text)
        self.assertTrue((await self._eval(_info(mergeable=None)))[0])  # GitHub is still computing: not a conflict

    async def test_revert_task_points_to_the_commit_before_the_merge(self):
        goals = [{"pr_number": 7, "title": "Кнопка правил", "review": {"merge_sha": "m1"}}]
        info = _info(paths=["bot/handlers/menu.py", "supabase/migrations/1.sql"])
        with patch.object(merge.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=goals))), \
                patch.object(github, "commit_parent", AsyncMock(return_value="p0")), patch.object(github, "pr_info", AsyncMock(return_value=info)):
            title, text = await merge.revert_task(7)
        self.assertEqual(title, "Откатить: Кнопка правил")
        self.assertIn("ref=p0", text)
        self.assertIn("bot/handlers/menu.py", text)
        self.assertNotIn("migrations", text)  # database changes are never rolled back by the agent

    async def test_revert_task_is_none_without_merge_data(self):
        for goals in ([], [{"pr_number": 7, "review": {}}]):
            with patch.object(merge.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=goals))):
                self.assertIsNone(await merge.revert_task(7))

    async def test_do_merge_remembers_merge_sha(self):
        save = AsyncMock(return_value=RPCResult(data={}))
        goals = [{"id": 4, "pr_number": 7, "title": "T", "review": {"verdict": "OK"}}]
        with patch.object(github, "pr_info", AsyncMock(return_value=_info())), patch.object(github, "ci", AsyncMock(return_value=GREEN)), \
                patch.object(github, "merge_pr", AsyncMock(return_value={"ok": True, "message": "", "sha": "m9"})), \
                patch.object(merge.rpc, "bot_agent_goals_list", AsyncMock(return_value=RPCResult(data=goals))), \
                patch.object(merge.rpc, "bot_agent_goal_save", save), patch.object(merge.rpc, "bot_agent_mem_add", AsyncMock()), \
                patch.object(merge.rpc, "bot_agent_journal_add", AsyncMock()):
            ok, _ = await merge.do_merge(7, owner=False, who="агентом сам")
        self.assertTrue(ok)
        self.assertEqual(save.await_args.args[1]["review"], {"verdict": "OK", "merge_sha": "m9"})


class GithubWrapperTests(unittest.IsolatedAsyncioTestCase):
    async def test_update_branch_sends_the_expected_head(self):
        send = AsyncMock(return_value=({"message": "Updating"}, None))
        with patch.object(github, "_send", send):
            self.assertIsNone(await github.update_branch(7, "abc"))
        self.assertEqual(send.await_args.args, ("PUT", "/pulls/7/update-branch", {"expected_head_sha": "abc"}))
        with patch.object(github, "_send", AsyncMock(return_value=(None, "HTTP 422"))):
            self.assertEqual(await github.update_branch(7, "abc"), "HTTP 422")

    async def test_merge_pr_reports_sha_and_errors(self):
        with patch.object(github, "_send", AsyncMock(return_value=({"merged": True, "sha": "s1", "message": "ok"}, None))) as send:
            out = await github.merge_pr(7, "Заголовок")
        self.assertEqual((out["ok"], out["sha"]), (True, "s1"))
        self.assertEqual(send.await_args.args[2]["merge_method"], "squash")
        with patch.object(github, "_send", AsyncMock(return_value=(None, "HTTP 405"))):
            self.assertEqual(await github.merge_pr(7, "x"), {"ok": False, "message": "HTTP 405", "sha": None})

    async def test_commit_parent(self):
        with patch.object(github, "_get", AsyncMock(return_value=({"parents": [{"sha": "p1"}]}, None))):
            self.assertEqual(await github.commit_parent("c"), "p1")
        with patch.object(github, "_get", AsyncMock(return_value=(None, "HTTP 404"))):
            self.assertIsNone(await github.commit_parent("c"))


def _goals_by_status(**by_status):
    async def goals(status=None, limit=20):
        return RPCResult(data=by_status.get(status, []))
    return goals


class ChooseWorkAutonomyTests(unittest.IsolatedAsyncioTestCase):
    RED = {"id": 3, "pr_number": 11, "title": "Красная", "head_sha": "abc", "merged_at": None, "review": {"ci": {"failed": 1, "pending": 0, "total": 3}}}

    async def _choose(self, state=None, redo=None, **by_status):
        save = AsyncMock(side_effect=lambda gid, patch_: RPCResult(data={"id": gid, "head_sha": "abc", **patch_}))
        redo = redo or AsyncMock(return_value=True)
        with patch.object(brain.rpc, "bot_agent_goals_list", _goals_by_status(**by_status)), patch.object(brain.rpc, "bot_agent_goal_save", save), \
                patch.object(brain.rpc, "bot_agent_mem_add", AsyncMock()), patch.object(brain.rpc, "bot_agent_state_patch", AsyncMock()), \
                patch.object(brain.autopilot, "redo", redo), \
                patch.object(github, "ci_details", AsyncMock(return_value={"failed": 1, "pending": 0, "failing": ["bot"], "failure_log": "ValueError: boom"})):
            return await brain._choose_work(state or {}), save, redo

    async def test_red_pr_out_of_attempts_is_rebuilt_when_autonomous(self):
        (goal, _, _), _, redo = await self._choose(state={"reworks": {"11": brain.MAX_REWORKS}}, done=[self.RED])
        self.assertIsNone(goal)
        redo.assert_awaited_once()
        self.assertIn("автопроверки", redo.await_args.args[1])

    async def test_reviewer_block_is_reworked_then_rebuilt(self):
        blocked = {**self.RED, "review": {"verdict": "BLOCK", "notes": "ломает меню", "ci": {"failed": 0, "pending": 0, "total": 3}}}
        (goal, hint, _), _, _ = await self._choose(done=[blocked])
        self.assertEqual(goal["id"], 3)
        self.assertIn("ломает меню", hint)
        (goal, _, _), _, redo = await self._choose(state={"reworks": {"11": brain.MAX_REWORKS}}, done=[blocked])
        self.assertIsNone(goal)
        self.assertIn("ревьюер", redo.await_args.args[1])

    async def test_manual_prs_are_never_reworked_or_rebuilt(self):
        manual = {**self.RED, "review": {**self.RED["review"], "manual": "self"}}
        (goal, _, _), _, redo = await self._choose(done=[manual])
        self.assertIsNone(goal)
        redo.assert_not_awaited()

    async def test_redo_task_is_picked_up_after_admin_tasks(self):
        paused = [{"id": 5, "source": "redo", "title": "Переделать: A", "expected": "e"}, {"id": 6, "source": "admin", "title": "B", "expected": "e"}]
        (goal, hint, _), _, _ = await self._choose(paused=paused)
        self.assertEqual(goal["id"], 6)
        (goal, hint, _), _, _ = await self._choose(paused=paused[:1])
        self.assertEqual(goal["id"], 5)
        self.assertIn("Переделать: A", hint)
        self.assertNotIn("ЗАДАЧА ОТ АДМИНА", hint)

    async def test_admin_task_does_not_cancel_a_started_rebuild(self):
        own = {"id": 1, "title": "Переделать: A", "source": "redo", "pr_number": None, "progress_pct": 5, "expected": "e"}
        (goal, _, _), save, _ = await self._choose(active=[own], paused=[{"id": 7, "source": "admin", "title": "T", "expected": "e"}])
        self.assertEqual(goal["id"], 1)
        save.assert_not_awaited()


class NotifyAutonomyTests(unittest.IsolatedAsyncioTestCase):
    def _goal(self, number, manual=None, total=3):
        return {"id": number, "pr_number": number, "health_pct": 100, "title": "T", "expected": "e", "branch": "agent/t",
                "review": {"plain": "Стало лучше", "verdict": "OK", "manual": manual, "ci": {"total": total, "failed": 0, "pending": 0}}}

    async def _run(self, goals, state):
        post = AsyncMock(return_value=SimpleNamespace(message_id=1))
        detail = AsyncMock(return_value=("card", None))
        with patch.object(brain.rpc, "bot_agent_state_patch", AsyncMock()), patch.object(brain.report, "waiting_goals", AsyncMock(return_value=goals)), \
                patch.object(brain.report, "post", post), patch.object(brain.report, "detail", detail):
            await brain._notify_ready(None, {"notified_prs": [], **state})
        return post, detail

    async def test_autonomous_mode_only_calls_a_human_for_manual_prs(self):
        post, detail = await self._run([self._goal(1), self._goal(2, manual="self"), self._goal(3, manual="migrations")], {"auto_merge": True})
        self.assertEqual([c.args[0] for c in detail.await_args_list], [2, 3])
        self.assertIn("моего собственного кода", detail.await_args_list[0].kwargs["header"])
        self.assertIn("миграция", detail.await_args_list[1].kwargs["header"])
        self.assertEqual(post.await_count, 2)

    async def test_manual_mode_announces_everything_ready(self):
        _, detail = await self._run([self._goal(1), self._goal(2, manual="self")], {"auto_merge": False})
        self.assertEqual([c.args[0] for c in detail.await_args_list], [1, 2])

    async def test_green_without_any_checks_is_not_announced(self):
        post, _ = await self._run([self._goal(1, manual="self", total=0)], {"auto_merge": True})
        post.assert_not_awaited()


class IdeaHintTests(unittest.IsolatedAsyncioTestCase):
    async def test_monitoring_mode_once_the_idea_pool_is_full(self):
        few = [{"id": i, "body": f"идея {i}"} for i in range(3)]
        full = [{"id": i, "body": f"идея {i}"} for i in range(brain.IDEA_POOL)]
        with patch.object(jobs, "ideas", AsyncMock(return_value=few)):
            hint = await brain._idea_hint()
        self.assertIn("РЕЖИМ ИДЕЙ", hint)
        self.assertIn("идея 0", hint)
        with patch.object(jobs, "ideas", AsyncMock(return_value=full)):
            self.assertIn("РЕЖИМ ПРОВЕРКИ ПРОДА", await brain._idea_hint())


class ReportAutonomyTests(unittest.IsolatedAsyncioTestCase):
    async def _build(self, state, done):
        with patch.object(report.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data=state))), \
                patch.object(report, "waiting_goals", AsyncMock(return_value=done)), \
                patch.object(report.rpc, "bot_agent_goals_list", _goals_by_status()):
            return (await report.build())[0]

    async def test_panel_splits_self_merging_from_needs_decision(self):
        goals = [{"id": 1, "pr_number": 1, "title": "A", "health_pct": 100, "review": {"plain": "Раз"}},
                 {"id": 2, "pr_number": 2, "title": "B", "health_pct": 100, "review": {"plain": "Два", "manual": "self"}}]
        text = await self._build({"auto_merge": True, "auto_merges": {"day": TODAY, "n": 4}}, goals)
        self.assertIn("сольётся само", text)
        self.assertIn("Нужно ваше решение", text)
        self.assertIn("Слито сегодня: 4", text)
        text = await self._build({"auto_merge": False}, goals)
        self.assertIn("ждёт вас", text)
        self.assertNotIn("сольётся само", text)

    async def test_status_line_for_checks_that_have_not_started(self):
        line = report._status_line({"health_pct": 100, "review": {"ci": {"total": 0}}})
        self.assertIn("не запускались", line)


class QuotaTests(unittest.IsolatedAsyncioTestCase):
    DAILY = ("HTTP 429: {'message': 'Daily free-tier limit reached for am/x: 1000 requests per quota day. "
             "Your allowance refills at 2099-01-01T21:00:00.000Z.', 'type': 'rate_limit_error'}")

    def setUp(self):
        brain._quota_until.clear()

    def tearDown(self):
        brain._quota_until.clear()

    def test_quota_error_is_recognised_and_capped(self):
        until = brain.quota_hit(brain.client.AIError(self.DAILY))
        self.assertGreater(until, time.time() + 5 * 3600)
        self.assertLessEqual(until, time.time() + 6 * 3600 + 5)  # a far refill date never parks the agent for days
        self.assertIsNone(brain.quota_hit(brain.client.AIError("HTTP 429: slow down")))
        self.assertIsNone(brain.quota_hit(brain.client.AIError("AI rate limit: budget exhausted, try again shortly")))
        self.assertGreater(brain.quota_hit(brain.client.AIError("Daily free-tier limit, no date")), time.time())

    async def test_exhausted_model_is_skipped_and_the_next_one_answers(self):
        calls = []

        async def chat(messages, **kw):
            calls.append(kw["model"])
            if kw["model"] == "m1":
                raise brain.client.AIError(self.DAILY)
            return {"content": "ok"}

        with patch.object(brain.client, "agent_models", lambda: ["m1", "m2"]), patch.object(brain.client, "chat", chat), \
                patch.object(brain.tools, "bump", AsyncMock()), patch.object(brain.client, "clear_pause") as clear:
            self.assertEqual((await brain._ask([]))["content"], "ok")
            self.assertEqual((await brain._ask([]))["content"], "ok")
        self.assertEqual(calls, ["m1", "m2", "m2"])  # m1 is asked once and then left alone until its allowance is back
        clear.assert_called_with("agent")
        self.assertEqual(brain.ai_ready_at(), 0.0)

    async def test_all_models_exhausted_fails_fast_without_calls(self):
        chat = AsyncMock()
        with patch.object(brain.client, "agent_models", lambda: ["m1"]), patch.object(brain.client, "chat", chat):
            brain._quota_until["m1"] = time.time() + 1000
            with self.assertRaises(brain.client.AIError):
                await brain._ask([])
            self.assertGreater(brain.ai_ready_at(), time.time())
        chat.assert_not_awaited()

    async def _cycle(self, state, ask_error=None):
        from services.agent import memory
        maintain = AsyncMock()
        posts = AsyncMock()
        patch_state = AsyncMock()
        with patch.object(brain.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data=state))), \
                patch.object(brain.client, "is_configured", lambda role="user": True), patch.object(brain, "_budget_ok", AsyncMock(return_value=True)), \
                patch.object(brain.rpc, "bot_agent_goals_list", _goals_by_status()), patch.object(brain.rpc, "bot_agent_inbox_take", AsyncMock(return_value=RPCResult(data=[]))), \
                patch.object(brain.report, "live", AsyncMock()), patch.object(brain.report, "post", posts), patch.object(brain, "_live_done", AsyncMock()), \
                patch.object(brain.rpc, "bot_agent_journal_add", AsyncMock()), patch.object(brain.rpc, "bot_agent_state_patch", patch_state), \
                patch.object(memory, "build_context", AsyncMock(return_value="ctx")), patch.object(brain.github, "tree_overview", AsyncMock(return_value="tree")), \
                patch.object(brain, "_maintain", maintain), patch.object(brain, "_ask", AsyncMock(side_effect=ask_error)):
            out = await brain.run_cycle(bot=None)
        return out, maintain, posts, patch_state

    async def test_ai_outage_still_runs_merging_and_waits_ten_minutes(self):
        out, maintain, posts, patch_state = await self._cycle({}, ask_error=brain.client.AIError("down"))
        self.assertFalse(out["ok"])
        maintain.assert_awaited_once()
        sent = patch_state.await_args.args[0]
        self.assertFalse(sent["ai_quota"])
        self.assertGreater(sent["ai_wait_until"], time.time() + 500)
        posts.assert_not_awaited()

    async def test_daily_quota_is_announced_once_and_cycles_then_skip_the_ai(self):
        def exhausted(*args, **kw):
            brain._quota_until["m1"] = time.time() + 7200  # what _ask records when the provider says the daily allowance is gone
            raise brain.client.AIError("HTTP 429 Daily free-tier limit")

        with patch.object(brain.client, "agent_models", lambda: ["m1"]):
            out, maintain, posts, patch_state = await self._cycle({}, ask_error=exhausted)
        sent = patch_state.await_args.args[0]
        self.assertTrue(sent["ai_quota"])
        posts.assert_awaited_once()
        self.assertIn("лимит ИИ", posts.await_args.args[1])
        waiting = {"ai_wait_until": time.time() + 3600}
        out, maintain, posts, _ = await self._cycle(waiting)
        self.assertTrue(out["ok"])
        maintain.assert_awaited_once()  # merges and conflict fixes go on while the AI sleeps
        posts.assert_not_awaited()

    async def test_paused_agent_does_not_merge(self):
        out, maintain, _, _ = await self._cycle({"paused": True})
        maintain.assert_not_awaited()


class HandlerTests(unittest.IsolatedAsyncioTestCase):
    def _message(self, text, user_id=1):
        reply = AsyncMock()
        return SimpleNamespace(text=text, message_id=10, reply=reply, reply_to_message=None, message_thread_id=config.THREAD_ID,
                               from_user=SimpleNamespace(id=user_id, username="adm", full_name="Adm")), reply

    async def _auto(self, text, perms):
        from handlers import agent_topic
        message, reply = self._message(text)
        patch_state = AsyncMock()
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True, "permissions": perms})), \
                patch.object(agent_topic.rpc, "bot_agent_state_get", AsyncMock(return_value=RPCResult(data={"auto_merge": True}))), \
                patch.object(agent_topic.rpc, "bot_agent_state_patch", patch_state):
            await agent_topic.admin_commands(message)
        return reply.await_args.args[0], patch_state

    async def test_agent_auto_switches_and_reports(self):
        text, patch_state = await self._auto("/agent_auto off", ["*"])
        patch_state.assert_awaited_once_with({"auto_merge": False})
        self.assertIn("выключено", text)
        text, patch_state = await self._auto("/agent_auto on", ["*"])
        patch_state.assert_awaited_once_with({"auto_merge": True})
        text, patch_state = await self._auto("/agent_auto", ["bans.view"])
        patch_state.assert_not_awaited()
        self.assertIn("включено", text)

    async def test_agent_auto_needs_a_head_admin(self):
        text, patch_state = await self._auto("/agent_auto off", ["bans.view"])
        patch_state.assert_not_awaited()
        self.assertIn("главные админы", text)

    async def _revert(self, found, perms=("*",)):
        from handlers import agent_topic
        callback = SimpleNamespace(data="agent:revert:7", answer=AsyncMock(), bot=None, from_user=SimpleNamespace(id=1, username="adm", full_name="Adm"),
                                   message=SimpleNamespace(chat=SimpleNamespace(id=config.CHAT_ID), message_thread_id=config.THREAD_ID, message_id=5))
        add, wake = AsyncMock(return_value=({"id": 30}, "")), AsyncMock()
        with patch.object(agent_topic, "staff_context", AsyncMock(return_value={"is_staff": True, "permissions": list(perms)})), \
                patch.object(agent_topic.merge, "revert_task", AsyncMock(return_value=found)), \
                patch.object(agent_topic.jobs, "add_task", add), patch.object(agent_topic.jobs, "wake", wake):
            await agent_topic.buttons(callback)
        return callback, add, wake

    async def test_revert_button_queues_an_admin_task_and_wakes_the_agent(self):
        callback, add, wake = await self._revert(("Откатить: A", "Откати изменения"))
        add.assert_awaited_once()
        self.assertEqual(add.await_args.kwargs, {"source": "admin", "title": "Откатить: A"})
        wake.assert_awaited_once()
        self.assertIn("Откатываю", callback.answer.await_args.args[0])

    async def test_revert_button_without_data_or_rights_does_nothing(self):
        callback, add, wake = await self._revert(None)
        add.assert_not_awaited()
        self.assertTrue(callback.answer.await_args.kwargs.get("show_alert"))
        callback, add, wake = await self._revert(("t", "x"), perms=("bans.view",))
        add.assert_not_awaited()
        self.assertIn("главные админы", callback.answer.await_args.args[0])


if __name__ == "__main__":
    unittest.main()
