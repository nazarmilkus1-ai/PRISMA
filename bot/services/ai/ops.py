"""Operations access for the admin PRISMA_AGENT: Render, Vercel and GitHub.

Everything is optional and driven by environment variables; nothing is configured by the bot itself.
Reads are always sanitised (secrets redacted, fields whitelisted). The only mutating call is a Render
redeploy, which exists solely behind a confirmation card for top staff.

  Render : RENDER_API_KEY, RENDER_SERVICE_ID
  Vercel : VERCEL_TOKEN, VERCEL_PROJECT_ID, (VERCEL_TEAM_ID)
  GitHub : GITHUB_TOKEN, GITHUB_REPO  (owner/repo), GITHUB_BASE_BRANCH (default PRISMA)

Code access: files can be read (secret-looking paths are refused and content is redacted). The agent can only
change code by opening a pull request from a fresh `agent/...` branch; it never merges and never touches the
base branch or CI workflows. That call exists solely behind a confirmation card.
"""
from __future__ import annotations

import base64
import os
import re
import time

import aiohttp

from services.ai.diagnostics import redact

_ID = re.compile(r"^[\w\-]{3,80}$")
_REPO = re.compile(r"^[\w.\-]+/[\w.\-]+$")


def _env(name: str) -> str:
    return os.getenv(name, "").strip()


def missing(*names: str) -> str | None:
    absent = [n for n in names if not _env(n)]
    return f"not configured: set {', '.join(absent)}" if absent else None


async def _request(method: str, url: str, headers: dict, params: dict | None = None, json_body: dict | None = None):
    try:
        timeout = aiohttp.ClientTimeout(total=20)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.request(method, url, headers=headers, params=params, json=json_body) as resp:
                data = await resp.json(content_type=None)
                if resp.status >= 300:
                    return None, f"HTTP {resp.status}"
                return data, None
    except Exception as exc:  # network errors must never crash the Copilot
        return None, type(exc).__name__


def _render_headers() -> dict:
    return {"Authorization": f"Bearer {_env('RENDER_API_KEY')}", "Accept": "application/json"}


def _vercel_params(extra: dict | None = None) -> dict:
    params = dict(extra or {})
    if _env("VERCEL_TEAM_ID"):
        params["teamId"] = _env("VERCEL_TEAM_ID")
    return params


def _short(value, n: int = 120) -> str:
    return redact(str(value or ""))[:n]


async def render_status() -> dict:
    if (err := missing("RENDER_API_KEY", "RENDER_SERVICE_ID")):
        return {"error": err}
    service_id = _env("RENDER_SERVICE_ID")
    if not _ID.match(service_id):
        return {"error": "bad RENDER_SERVICE_ID"}
    data, err = await _request("GET", f"https://api.render.com/v1/services/{service_id}/deploys",
                               _render_headers(), {"limit": 5})
    if err:
        return {"error": f"Render {err}"}
    deploys = []
    for item in data if isinstance(data, list) else []:
        deploy = item.get("deploy", item) if isinstance(item, dict) else {}
        commit = deploy.get("commit") or {}
        deploys.append({"id": deploy.get("id"), "status": deploy.get("status"), "trigger": deploy.get("trigger"),
                        "commit": _short(commit.get("message"), 80), "created": deploy.get("createdAt"),
                        "finished": deploy.get("finishedAt")})
    return {"deploys": deploys}


async def render_logs(limit: int = 40) -> dict:
    if (err := missing("RENDER_API_KEY", "RENDER_SERVICE_ID")):
        return {"error": err}
    service_id = _env("RENDER_SERVICE_ID")
    if not _ID.match(service_id):
        return {"error": "bad RENDER_SERVICE_ID"}
    service, err = await _request("GET", f"https://api.render.com/v1/services/{service_id}", _render_headers())
    owner = (service or {}).get("ownerId") if isinstance(service, dict) else None
    if err or not owner:
        return {"error": f"Render {err or 'no owner'}"}
    data, err = await _request("GET", "https://api.render.com/v1/logs", _render_headers(),
                               {"ownerId": owner, "resource": service_id, "limit": max(5, min(80, limit)), "direction": "backward"})
    if err:
        return {"error": f"Render {err}"}
    logs = data.get("logs") if isinstance(data, dict) else []
    return {"logs": [_short(row.get("message"), 240) for row in (logs or [])[:80] if isinstance(row, dict)]}


async def render_redeploy() -> tuple[bool, str]:
    if (err := missing("RENDER_API_KEY", "RENDER_SERVICE_ID")):
        return False, err
    service_id = _env("RENDER_SERVICE_ID")
    if not _ID.match(service_id):
        return False, "bad RENDER_SERVICE_ID"
    data, err = await _request("POST", f"https://api.render.com/v1/services/{service_id}/deploys",
                               _render_headers(), json_body={"clearCache": "do_not_clear"})
    return (err is None), (err or f"deploy {_short((data or {}).get('id'), 30)} started")


async def vercel_status() -> dict:
    if (err := missing("VERCEL_TOKEN", "VERCEL_PROJECT_ID")):
        return {"error": err}
    headers = {"Authorization": f"Bearer {_env('VERCEL_TOKEN')}"}
    data, err = await _request("GET", "https://api.vercel.com/v6/deployments", headers,
                               _vercel_params({"projectId": _env("VERCEL_PROJECT_ID"), "limit": 6}))
    if err:
        return {"error": f"Vercel {err}"}
    out = []
    for d in (data or {}).get("deployments", [])[:6]:
        meta = d.get("meta") or {}
        out.append({"id": d.get("uid"), "state": d.get("state") or d.get("readyState"), "target": d.get("target") or "preview",
                    "branch": _short(meta.get("githubCommitRef"), 60), "commit": _short(meta.get("githubCommitMessage"), 80),
                    "created": d.get("created")})
    return {"deployments": out}


async def vercel_deployment(deployment_id: str) -> dict:
    if (err := missing("VERCEL_TOKEN", "VERCEL_PROJECT_ID")):
        return {"error": err}
    if not _ID.match(deployment_id or ""):
        return {"error": "bad deployment id"}
    headers = {"Authorization": f"Bearer {_env('VERCEL_TOKEN')}"}
    data, err = await _request("GET", f"https://api.vercel.com/v13/deployments/{deployment_id}", headers, _vercel_params())
    if err:
        return {"error": f"Vercel {err}"}
    return {"state": data.get("readyState"), "error_code": data.get("errorCode"),
            "error_message": _short(data.get("errorMessage"), 300)}


async def github_status() -> dict:
    if (err := missing("GITHUB_TOKEN", "GITHUB_REPO")):
        return {"error": err}
    repo = _env("GITHUB_REPO")
    if not _REPO.match(repo):
        return {"error": "bad GITHUB_REPO"}
    headers = {"Authorization": f"Bearer {_env('GITHUB_TOKEN')}", "Accept": "application/vnd.github+json"}
    prs, err = await _request("GET", f"https://api.github.com/repos/{repo}/pulls", headers, {"state": "open", "per_page": 10})
    if err:
        return {"error": f"GitHub {err}"}
    out = [{"number": p.get("number"), "title": _short(p.get("title"), 80), "branch": _short((p.get("head") or {}).get("ref"), 50),
            "draft": p.get("draft")} for p in prs if isinstance(p, dict)]
    issues, _ = await _request("GET", f"https://api.github.com/repos/{repo}/issues", headers,
                               {"state": "open", "labels": "from-copilot", "per_page": 5})
    return {"open_pull_requests": out,
            "open_copilot_issues": [{"number": i.get("number"), "title": _short(i.get("title"), 80)}
                                    for i in (issues or []) if isinstance(i, dict) and "pull_request" not in i]}


# ---------------------------------------------------------------- code access (GitHub)

_BLOCKED_PATH = re.compile(
    r"(^|/)(\.env[^/]*|[^/]*\.env|[^/]*secret[^/]*|[^/]*\.pem|[^/]*\.key|id_rsa[^/]*|\.git/.*)$", re.I)
_PROTECTED_WRITE = ("/.github/", ".github/", "node_modules/", ".git/")
MAX_FILES = 5
MAX_FILE_CHARS = 60_000
READ_CHARS = 12_000


def _gh_headers() -> dict:
    return {"Authorization": f"Bearer {_env('GITHUB_TOKEN')}", "Accept": "application/vnd.github+json"}


def _gh_repo() -> tuple[str | None, str | None]:
    if (err := missing("GITHUB_TOKEN", "GITHUB_REPO")):
        return None, err
    repo = _env("GITHUB_REPO")
    return (repo, None) if _REPO.match(repo) else (None, "bad GITHUB_REPO")


def safe_path(path: str) -> str | None:
    path = (path or "").strip().lstrip("/")
    if not path or len(path) > 200 or ".." in path.split("/") or "\\" in path or _BLOCKED_PATH.search(path):
        return None
    return path


async def github_read(path: str) -> dict:
    repo, err = _gh_repo()
    if err:
        return {"error": err}
    path = safe_path(path)
    if not path:
        return {"error": "path not allowed"}
    ref = _env("GITHUB_BASE_BRANCH") or "PRISMA"
    data, err = await _request("GET", f"https://api.github.com/repos/{repo}/contents/{path}", _gh_headers(), {"ref": ref})
    if err:
        return {"error": f"GitHub {err}"}
    if isinstance(data, list):
        return {"directory": path, "entries": [{"name": e.get("name"), "type": e.get("type")} for e in data[:80] if isinstance(e, dict)]}
    if not isinstance(data, dict) or data.get("encoding") != "base64":
        return {"error": "not a text file"}
    try:
        text = base64.b64decode(data.get("content") or "").decode("utf-8")
    except Exception:
        return {"error": "binary file"}
    return {"path": path, "ref": ref, "truncated": len(text) > READ_CHARS, "content": redact(text[:READ_CHARS])}


def validate_change(files: list) -> tuple[list[dict] | None, str | None]:
    if not isinstance(files, list) or not files:
        return None, "files required"
    if len(files) > MAX_FILES:
        return None, f"at most {MAX_FILES} files per change"
    out = []
    for f in files:
        if not isinstance(f, dict):
            return None, "bad file entry"
        path = safe_path(str(f.get("path") or ""))
        content = f.get("content")
        if not path or any(path.startswith(p) or p in path for p in _PROTECTED_WRITE):
            return None, f"path not allowed: {str(f.get('path'))[:80]}"
        if not isinstance(content, str) or len(content) > MAX_FILE_CHARS:
            return None, f"content missing or too large: {path}"
        out.append({"path": path, "content": content})
    return out, None


async def github_open_pr(title: str, body: str, files: list[dict]) -> tuple[bool, str]:
    """Create a fresh branch, commit the files and open a PR. Never merges; never writes to the base branch."""
    repo, err = _gh_repo()
    if err:
        return False, err
    base = _env("GITHUB_BASE_BRANCH") or "PRISMA"
    h = _gh_headers()
    ref, err = await _request("GET", f"https://api.github.com/repos/{repo}/git/ref/heads/{base}", h)
    if err:
        return False, f"base branch: {err}"
    sha = ((ref or {}).get("object") or {}).get("sha")
    branch = f"agent/{time.strftime('%Y%m%d-%H%M%S')}"
    _, err = await _request("POST", f"https://api.github.com/repos/{repo}/git/refs", h,
                            json_body={"ref": f"refs/heads/{branch}", "sha": sha})
    if err:
        return False, f"create branch: {err}"
    for f in files:
        url = f"https://api.github.com/repos/{repo}/contents/{f['path']}"
        existing, _e = await _request("GET", url, h, {"ref": branch})
        payload = {"message": f"agent: {title[:60]}", "branch": branch,
                   "content": base64.b64encode(f["content"].encode("utf-8")).decode()}
        if isinstance(existing, dict) and existing.get("sha"):
            payload["sha"] = existing["sha"]
        _, err = await _request("PUT", url, h, json_body=payload)
        if err:
            return False, f"commit {f['path']}: {err}"
    pr, err = await _request("POST", f"https://api.github.com/repos/{repo}/pulls", h, json_body={
        "title": title[:120], "head": branch, "base": base,
        "body": (body or "")[:3000] + "\n\n_Открыто PRISMA_AGENT после подтверждения администратором. Не слито — проверь и смержи сам._"})
    if err:
        return False, f"open PR: {err}"
    return True, f"PR #{(pr or {}).get('number')}: {(pr or {}).get('html_url')}"
