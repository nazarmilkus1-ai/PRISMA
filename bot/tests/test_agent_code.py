import unittest
from unittest.mock import AsyncMock, patch

from services.ai import ops


class SafePathTests(unittest.TestCase):
    def test_blocks_secrets_and_traversal(self):
        for bad in ["../x", "a/../b", ".env", "bot/.env.local", "render.env", "keys/server.pem", "my_secret.txt", ".git/config", ""]:
            self.assertIsNone(ops.safe_path(bad), bad)

    def test_allows_normal_code(self):
        self.assertEqual(ops.safe_path("/bot/main.py"), "bot/main.py")
        self.assertEqual(ops.safe_path("panel/src/lib/guardian.ts"), "panel/src/lib/guardian.ts")


class ValidateChangeTests(unittest.TestCase):
    def test_rejects_workflows_and_too_many(self):
        self.assertIsNotNone(ops.validate_change([{"path": ".github/workflows/x.yml", "content": "a"}])[1])
        self.assertIsNotNone(ops.validate_change([{"path": f"a{i}.py", "content": "x"} for i in range(6)])[1])
        self.assertIsNotNone(ops.validate_change([])[1])
        self.assertIsNotNone(ops.validate_change([{"path": "a.py", "content": "x" * (ops.MAX_FILE_CHARS + 1)}])[1])

    def test_accepts_ok(self):
        files, err = ops.validate_change([{"path": "bot/a.py", "content": "print(1)"}])
        self.assertIsNone(err)
        self.assertEqual(files[0]["path"], "bot/a.py")


class OpenPrTests(unittest.IsolatedAsyncioTestCase):
    async def test_never_touches_base_branch_and_opens_pr(self):
        calls = []

        async def fake(method, url, headers, params=None, json_body=None):
            calls.append((method, url, json_body))
            if method == "GET" and "/git/ref/heads/" in url:
                return {"object": {"sha": "abc"}}, None
            if method == "GET":
                return None, "HTTP 404"
            if url.endswith("/pulls"):
                return {"number": 7, "html_url": "https://x/7"}, None
            return {}, None

        env = {"GITHUB_TOKEN": "t", "GITHUB_REPO": "o/r"}
        with patch.dict("os.environ", env), patch.object(ops, "_request", fake):
            ok, detail = await ops.github_open_pr("Fix thing", "why", [{"path": "bot/a.py", "content": "x"}])
        self.assertTrue(ok)
        self.assertIn("#7", detail)
        puts = [c for c in calls if c[0] == "PUT"]
        self.assertTrue(puts and all(c[2]["branch"].startswith("agent/") for c in puts))
        self.assertFalse(any("merge" in c[1] for c in calls))

    async def test_missing_token(self):
        with patch.dict("os.environ", {"GITHUB_TOKEN": "", "GITHUB_REPO": ""}):
            ok, detail = await ops.github_open_pr("t", "b", [])
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()


class RateLimitTests(unittest.IsolatedAsyncioTestCase):
    async def test_budget_exhausted_fails_fast(self):
        from services.ai import client
        client._calls.clear()
        client._paused_until.clear()
        with patch.dict("os.environ", {"AI_RPM_ADMIN": "2"}), patch.object(client, "_MAX_WAIT", 0.0):
            await client._acquire("admin")
            await client._acquire("admin")
            with self.assertRaises(client.AIError):
                await client._acquire("admin")
        client._calls.clear()

    async def test_429_pause_blocks_next_call(self):
        from services.ai import client
        client._calls.clear()
        client._paused_until.clear()
        client._pause("user", 30)
        with patch.object(client, "_MAX_WAIT", 0.0):
            with self.assertRaises(client.AIError):
                await client._acquire("user")
        client._paused_until.clear()
