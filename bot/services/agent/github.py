"""GitHub access for the agent: branches, atomic commits, PRs, CI health, diffs and the (button-only) merge."""
from __future__ import annotations

import base64
import re
import time

from services.ai import ops
from services.ai.diagnostics import redact

from . import config

_BRANCH_OK = re.compile(r"^agent/[a-z0-9][a-z0-9._\-/]{2,100}$")
_API = "https://api.github.com"


def slug(text: str) -> str:
    table = {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "y",
             "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
             "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
             "і": "i", "ї": "yi", "є": "ye", "ґ": "g"}
    out = "".join(table.get(ch, ch) for ch in (text or "").lower())
    out = re.sub(r"[^a-z0-9]+", "-", out).strip("-")
    return (out or "work")[:40].strip("-") or "work"


def new_branch_name(title: str) -> str:
    return f"{config.BRANCH_PREFIX}{slug(title)}-{time.strftime('%m%d-%H%M')}"


def valid_branch(name: str) -> bool:
    return bool(_BRANCH_OK.match(name or "")) and ".." not in name


def _repo() -> tuple[str | None, str | None]:
    return ops._gh_repo()


async def _get(path: str, params: dict | None = None, headers: dict | None = None):
    repo, err = _repo()
    if err:
        return None, err
    return await ops._request("GET", f"{_API}/repos/{repo}{path}", {**ops._gh_headers(), **(headers or {})}, params)


async def _send(method: str, path: str, body: dict | None = None):
    repo, err = _repo()
    if err:
        return None, err
    return await ops._request(method, f"{_API}/repos/{repo}{path}", ops._gh_headers(), json_body=body)


def check_write_path(path: str) -> str | None:
    """Return a clean path, or None when the agent must not write it."""
    clean = ops.safe_path(path)
    if not clean:
        return None
    if clean.startswith(config.WRITE_BLOCKED_PREFIXES) or clean.split("/")[-1] in config.WRITE_BLOCKED_NAMES:
        return None
    return clean


def validate_files(files) -> tuple[list[dict] | None, str | None]:
    if not isinstance(files, list) or not files:
        return None, "files required"
    if len(files) > config.MAX_FILES_PER_COMMIT:
        return None, f"at most {config.MAX_FILES_PER_COMMIT} files per commit"
    out, seen = [], set()
    for item in files:
        if not isinstance(item, dict):
            return None, "bad file entry"
        path = check_write_path(str(item.get("path") or ""))
        if not path:
            return None, f"path not allowed: {str(item.get('path'))[:80]}"
        if path in seen:
            return None, f"duplicate path: {path}"
        seen.add(path)
        if item.get("delete") is True:
            out.append({"path": path, "delete": True})
            continue
        content = item.get("content")
        if not isinstance(content, str) or len(content) > config.MAX_FILE_CHARS:
            return None, f"content missing or too large: {path}"
        out.append({"path": path, "content": content})
    return out, None


async def read(path: str, ref: str | None = None, limit: int = 20_000) -> dict:
    clean = ops.safe_path(path)
    if not clean:
        return {"error": "path not allowed"}
    data, err = await _get(f"/contents/{clean}", {"ref": ref or config.BASE_BRANCH})
    if err:
        return {"error": f"GitHub {err}"}
    if isinstance(data, list):
        return {"directory": clean, "entries": [{"name": e.get("name"), "type": e.get("type")} for e in data[:100] if isinstance(e, dict)]}
    if not isinstance(data, dict) or data.get("encoding") != "base64":
        return {"error": "not a text file"}
    try:
        text = base64.b64decode(data.get("content") or "").decode("utf-8")
    except Exception:
        return {"error": "binary file"}
    return {"path": clean, "ref": ref or config.BASE_BRANCH, "size": len(text), "truncated": len(text) > limit, "content": redact(text[:limit])}


async def search(query: str) -> dict:
    repo, err = _repo()
    if err:
        return {"error": err}
    q = re.sub(r"[^\w .\-/]", " ", query or "")[:120].strip()
    if not q:
        return {"error": "empty query"}
    data, err = await ops._request(
        "GET", f"{_API}/search/code", {**ops._gh_headers(), "Accept": "application/vnd.github.text-match+json"},
        {"q": f"{q} repo:{repo}", "per_page": 10})
    if err:
        return {"error": f"GitHub {err}"}
    hits = []
    for item in (data or {}).get("items", [])[:10]:
        frag = ""
        for match in item.get("text_matches") or []:
            frag = redact(str(match.get("fragment") or ""))[:240]
            break
        hits.append({"path": item.get("path"), "match": frag})
    return {"hits": hits}


async def branch_head(branch: str) -> str | None:
    data, err = await _get(f"/git/ref/heads/{branch}")
    return ((data or {}).get("object") or {}).get("sha") if not err else None


async def ensure_branch(branch: str) -> tuple[str | None, str | None]:
    """Create `branch` from the base branch if it does not exist. Never touches the base branch itself."""
    if not valid_branch(branch):
        return None, "branch name not allowed"
    head = await branch_head(branch)
    if head:
        return head, None
    base = await branch_head(config.BASE_BRANCH)
    if not base:
        return None, "base branch not found"
    _, err = await _send("POST", "/git/refs", {"ref": f"refs/heads/{branch}", "sha": base})
    if err:
        return None, f"create branch: {err}"
    return base, None


async def commit_files(branch: str, files: list[dict], message: str) -> tuple[str | None, str | None]:
    """One atomic commit with several files on an agent/* branch."""
    if not valid_branch(branch):
        return None, "branch name not allowed"
    parent = await branch_head(branch)
    if not parent:
        return None, "branch not found"
    commit, err = await _get(f"/git/commits/{parent}")
    if err:
        return None, f"read commit: {err}"
    base_tree = ((commit or {}).get("tree") or {}).get("sha")
    tree = []
    for f in files:
        if f.get("delete"):
            tree.append({"path": f["path"], "mode": "100644", "type": "blob", "sha": None})
            continue
        blob, err = await _send("POST", "/git/blobs", {"content": f["content"], "encoding": "utf-8"})
        if err or not (blob or {}).get("sha"):
            return None, f"blob {f['path']}: {err}"
        tree.append({"path": f["path"], "mode": "100644", "type": "blob", "sha": blob["sha"]})
    new_tree, err = await _send("POST", "/git/trees", {"base_tree": base_tree, "tree": tree})
    if err:
        return None, f"tree: {err}"
    created, err = await _send("POST", "/git/commits", {"message": message[:300], "tree": new_tree["sha"], "parents": [parent]})
    if err:
        return None, f"commit: {err}"
    _, err = await _send("PATCH", f"/git/refs/heads/{branch}", {"sha": created["sha"], "force": False})
    if err:
        return None, f"update ref: {err}"
    return created["sha"], None


async def find_pr(branch: str) -> dict | None:
    repo, err = _repo()
    if err:
        return None
    owner = repo.split("/")[0]
    data, err = await _get("/pulls", {"head": f"{owner}:{branch}", "state": "all", "per_page": 1})
    if err or not isinstance(data, list) or not data:
        return None
    return data[0]


async def open_pr(branch: str, title: str, body: str) -> tuple[dict | None, str | None]:
    existing = await find_pr(branch)
    if existing and existing.get("state") == "open":
        return existing, None
    pr, err = await _send("POST", "/pulls", {"title": title[:120], "head": branch, "base": config.BASE_BRANCH, "body": body[:3500]})
    return pr, err


async def update_pr(number: int, title: str | None = None, body: str | None = None) -> str | None:
    patch = {}
    if title:
        patch["title"] = title[:120]
    if body:
        patch["body"] = body[:3500]
    if not patch:
        return None
    _, err = await _send("PATCH", f"/pulls/{int(number)}", patch)
    return err


def summarize_checks(runs: list[dict]) -> dict:
    """Health = share of finished, non-skipped checks that passed; pending checks count against it."""
    passed = failed = pending = 0
    failing: list[str] = []
    for run in runs:
        if run.get("status") != "completed":
            pending += 1
            continue
        conclusion = run.get("conclusion")
        if conclusion in {"skipped", "neutral", "cancelled"} and conclusion != "cancelled":
            continue
        if conclusion == "success":
            passed += 1
        else:
            failed += 1
            failing.append(str(run.get("name")))
    total = passed + failed + pending
    health = 100 if total == 0 else round(100 * passed / total)
    return {"total": total, "passed": passed, "failed": failed, "pending": pending, "health_pct": health, "failing": failing[:8]}


async def ci(sha: str) -> dict:
    if not sha:
        return {"error": "no commit yet"}
    data, err = await _get(f"/commits/{sha}/check-runs", {"per_page": 100})
    if err:
        return {"error": f"GitHub {err}"}
    return summarize_checks((data or {}).get("check_runs") or [])


async def compare(base: str, head: str, max_chars: int = 28_000) -> dict:
    data, err = await _get(f"/compare/{base}...{head}", {"per_page": 100})
    if err:
        return {"error": f"GitHub {err}"}
    files = (data or {}).get("files") or []
    listing = [{"path": f.get("filename"), "status": f.get("status"), "add": f.get("additions"), "del": f.get("deletions")} for f in files]
    chunks, used = [], 0
    for f in files:
        patch = f"--- {f.get('filename')}\n{f.get('patch') or '(binary or too large)'}\n"
        if used + len(patch) > max_chars:
            chunks.append(f"... diff truncated, {len(files) - len(chunks)} more files")
            break
        chunks.append(patch)
        used += len(patch)
    return {"files": listing, "ahead_by": (data or {}).get("ahead_by"), "diff": redact("".join(chunks))}


def classify_paths(paths: list[str]) -> dict:
    return {
        "refused": [p for p in paths if p.startswith(config.MERGE_REFUSED_PREFIXES)],
        "self": [p for p in paths if p.startswith(config.SELF_PREFIXES)],
    }


async def pr_info(number: int) -> dict:
    pr, err = await _get(f"/pulls/{int(number)}")
    if err:
        return {"error": f"GitHub {err}"}
    files, ferr = await _get(f"/pulls/{int(number)}/files", {"per_page": 100})
    paths = [f.get("filename") for f in (files or [])] if not ferr and isinstance(files, list) else []
    return {
        "number": pr.get("number"), "state": pr.get("state"), "merged": bool(pr.get("merged")), "title": pr.get("title"),
        "head_ref": (pr.get("head") or {}).get("ref"), "head_sha": (pr.get("head") or {}).get("sha"),
        "url": pr.get("html_url"), "paths": paths, "mergeable": pr.get("mergeable"),
    }


async def merge(number: int, title: str) -> tuple[bool, str]:
    """Squash-merge into the base branch. Only ever called from the admin's merge button."""
    data, err = await _send("PUT", f"/pulls/{int(number)}/merge", {"merge_method": "squash", "commit_title": title[:200]})
    if err:
        return False, err
    return bool((data or {}).get("merged")), str((data or {}).get("message") or "")
