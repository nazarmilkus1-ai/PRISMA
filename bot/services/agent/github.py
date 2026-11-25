"""GitHub access for the agent: branches, atomic commits, PRs, CI health, diffs and the (button-only) merge."""
from __future__ import annotations

import base64
import io
import re
import time
import zipfile

import aiohttp

from services.ai import ops
from services.ai.diagnostics import redact

from . import checks, config

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


async def read(path: str, ref: str | None = None, limit: int = 20_000, start: int | None = None, end: int | None = None) -> dict:
    """Whole file (first `limit` chars) or, with start/end, a numbered slice of lines so huge files can be read in parts."""
    clean = ops.safe_path(path)
    if not clean:
        return {"error": "path not allowed"}
    data, err = await _get(f"/contents/{clean}", {"ref": ref or config.BASE_BRANCH})
    if err:
        return {"error": f"GitHub {err}" + (" (такого пути нет — смотри список файлов в контексте)" if err.endswith("404") else "")}
    if isinstance(data, list):
        return {"directory": clean, "entries": [{"name": e.get("name"), "type": e.get("type")} for e in data[:100] if isinstance(e, dict)]}
    if not isinstance(data, dict) or data.get("encoding") != "base64":
        return {"error": "not a text file"}
    try:
        text = base64.b64decode(data.get("content") or "").decode("utf-8")
    except Exception:
        return {"error": "binary file"}
    lines = text.split("\n")
    if start or end:
        first = max(1, int(start or 1))
        last = min(len(lines), int(end or first + 119), first + 399)
        if first > len(lines):
            return {"error": f"в файле всего {len(lines)} строк"}
        chunk = "\n".join(f"{i}: {lines[i - 1]}" for i in range(first, last + 1))
        return {"path": clean, "ref": ref or config.BASE_BRANCH, "lines": f"{first}-{last} из {len(lines)}",
                "note": "номера «N: » в начале строк — не часть файла, в old_str их не копируй", "content": redact(chunk[:limit])}
    out = {"path": clean, "ref": ref or config.BASE_BRANCH, "size": len(text), "lines": len(lines), "truncated": len(text) > limit,
           "content": redact(text[:limit])}
    if out["truncated"]:
        out["hint"] = f"файл большой ({len(lines)} строк): остальное читай кусками через start/end"
    return out


async def read_raw(path: str, ref: str | None = None) -> tuple[str | None, str | None]:
    """Unredacted file text for edits (the redacted copy given to the model must never be written back)."""
    clean = ops.safe_path(path)
    if not clean:
        return None, "path not allowed"
    data, err = await _get(f"/contents/{clean}", {"ref": ref or config.BASE_BRANCH})
    if err or not isinstance(data, dict) or data.get("encoding") != "base64":
        return None, err or "not a text file"
    try:
        return base64.b64decode(data.get("content") or "").decode("utf-8"), None
    except Exception:
        return None, "binary file"


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
    failing_ids: list[int] = []
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
            if run.get("id"):
                failing_ids.append(int(run["id"]))
    total = passed + failed + pending
    health = 100 if total == 0 else round(100 * passed / total)
    return {"total": total, "passed": passed, "failed": failed, "pending": pending, "health_pct": health, "failing": failing[:8],
            "failing_ids": failing_ids[:4]}


async def ci(sha: str) -> dict:
    if not sha:
        return {"error": "no commit yet"}
    data, err = await _get(f"/commits/{sha}/check-runs", {"per_page": 100})
    if err:
        return {"error": f"GitHub {err}"}
    return summarize_checks((data or {}).get("check_runs") or [])


async def read_capped(resp, limit: int) -> tuple[bytes, bool]:
    """Whole response body up to `limit` bytes (StreamReader.read(n) returns only the first available chunk, not the body)."""
    chunks: list[bytes] = []
    size = 0
    async for chunk in resp.content.iter_chunked(65_536):
        size += len(chunk)
        if size > limit:
            chunks.append(chunk[: len(chunk) - (size - limit)])
            return b"".join(chunks), True
        chunks.append(chunk)
    return b"".join(chunks), False


async def job_log(job_id: int, max_bytes: int = 3_000_000) -> str | None:
    """Raw log of one GitHub Actions job (check-run id == job id). Needs actions:read; returns None when unavailable."""
    repo, err = _repo()
    if err:
        return None
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=25)) as session:
            async with session.get(f"{_API}/repos/{repo}/actions/jobs/{int(job_id)}/logs", headers=ops._gh_headers()) as resp:
                if resp.status >= 300:
                    return None
                body, _ = await read_capped(resp, max_bytes)
                return body.decode("utf-8", "ignore")
    except Exception:
        return None


async def ci_details(sha: str) -> dict:
    """CI summary plus, for failed checks, the few log lines that explain the failure."""
    out = await ci(sha)
    if out.get("error") or not out.get("failed"):
        return out
    reasons = []
    for job_id in out.get("failing_ids", [])[:2]:
        log = await job_log(job_id)
        if log:
            reasons.append(redact(checks.failure_excerpt(log)))
    if reasons:
        out["failure_log"] = "\n---\n".join(r for r in reasons if r)[:4000]
    else:
        out["failure_log"] = "(лог упавшей проверки недоступен — перечитай свой код: синтаксис, импорты, существующие тесты)"
    return out


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
        "url": pr.get("html_url"), "paths": paths, "mergeable": pr.get("mergeable"), "mergeable_state": pr.get("mergeable_state"),
    }


async def update_branch(number: int, head_sha: str) -> str | None:
    """Merge the base branch into the PR branch (what the «Update branch» button does). None = accepted; 'HTTP 422' = real conflict."""
    _, err = await _send("PUT", f"/pulls/{int(number)}/update-branch", {"expected_head_sha": head_sha})
    return err


async def commit_parent(sha: str) -> str | None:
    data, err = await _get(f"/commits/{sha}")
    parents = (data or {}).get("parents") if not err and isinstance(data, dict) else None
    return (parents or [{}])[0].get("sha") if parents else None


async def close_pr(number: int) -> str | None:
    _, err = await _send("PATCH", f"/pulls/{int(number)}", {"state": "closed"})
    return err


async def merge_pr(number: int, title: str) -> dict:
    """Squash-merge into the base branch: {ok, message, sha}. Callers are the merge gate (button) and the autopilot, both behind evaluate()."""
    data, err = await _send("PUT", f"/pulls/{int(number)}/merge", {"merge_method": "squash", "commit_title": title[:200]})
    if err:
        return {"ok": False, "message": err, "sha": None}
    return {"ok": bool((data or {}).get("merged")), "message": str((data or {}).get("message") or ""), "sha": (data or {}).get("sha")}


async def merge(number: int, title: str) -> tuple[bool, str]:
    out = await merge_pr(number, title)
    return out["ok"], out["message"]


_tree_cache: dict = {"at": 0.0, "text": ""}


async def tree_overview(max_paths: int = 260) -> str:
    """Compact list of source files so the agent does not waste steps walking directories one by one (cached 10 min)."""
    if time.monotonic() - _tree_cache["at"] < 600 and _tree_cache["text"]:
        return _tree_cache["text"]
    data, err = await _get(f"/git/trees/{config.BASE_BRANCH}", {"recursive": "1"})
    if err or not isinstance(data, dict):
        return _tree_cache["text"] or "(структура репозитория недоступна — используй repo_read)"
    keep = ("bot/", "site/src/", "panel/src/", "minecraft-plugin/src/", "docs/", "scripts/")
    skip = ("/__pycache__/", ".png", ".jpg", ".svg", ".ico", ".lock", "/tests/")
    paths = [t["path"] for t in data.get("tree", []) if t.get("type") == "blob" and t["path"].startswith(keep)
             and not any(x in t["path"] for x in skip)]
    text = "\n".join(paths[:max_paths]) + (f"\n… и ещё {len(paths) - max_paths} файлов" if len(paths) > max_paths else "")
    _tree_cache["at"], _tree_cache["text"] = time.monotonic(), text
    return text


_preview_cache: dict = {}


async def preview_url(branch: str) -> str | None:
    """Vercel preview of an agent branch (only exists when the branch touches site/panel). Best effort, cached 5 min."""
    hit = _preview_cache.get(branch)
    if hit and time.monotonic() - hit[0] < 300:
        return hit[1]
    url = None
    if not ops.missing("VERCEL_TOKEN", "VERCEL_PROJECT_ID") and valid_branch(branch):
        data, err = await ops._request("GET", "https://api.vercel.com/v6/deployments", {"Authorization": f"Bearer {ops._env('VERCEL_TOKEN')}"},
                                       ops._vercel_params({"projectId": ops._env("VERCEL_PROJECT_ID"), "limit": 20}))
        if not err:
            for d in (data or {}).get("deployments", []):
                if (d.get("meta") or {}).get("githubCommitRef") == branch and (d.get("state") or d.get("readyState")) == "READY" and d.get("url"):
                    url = "https://" + d["url"]
                    break
    _preview_cache[branch] = (time.monotonic(), url)
    return url


_zip_cache: dict = {"at": 0.0, "files": {}}
_TEXT_PREFIXES = ("bot/", "site/", "panel/", "minecraft-plugin/", "docs/", "scripts/", "supabase/", "packages/", "modules/")
_SKIP_PARTS = ("node_modules/", "/.next/", "package-lock.json", "/build/", "/dist/")
_TEXT_EXT = (".py", ".ts", ".tsx", ".js", ".mjs", ".json", ".java", ".kt", ".sql", ".md", ".yml", ".yaml", ".css", ".txt", ".gradle", ".toml", ".html")


def parse_zip(raw: bytes) -> dict[str, str]:
    """GitHub zipball bytes -> {path: text} for source-like text files only (binary, huge and generated files are skipped)."""
    files: dict[str, str] = {}
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            for info in archive.infolist():
                name = info.filename.split("/", 1)[1] if "/" in info.filename else ""
                if (info.is_dir() or not name.startswith(_TEXT_PREFIXES) or not name.endswith(_TEXT_EXT) or info.file_size > 250_000
                        or any(part in name for part in _SKIP_PARTS)):
                    continue
                try:
                    files[name] = archive.read(info).decode("utf-8")
                except (UnicodeDecodeError, KeyError):
                    continue
    except zipfile.BadZipFile:
        return {}
    return files


async def _repo_files() -> dict[str, str]:
    """Whole base branch as {path: text}, from one zip download cached for 10 minutes (≈2 MB): grep without GitHub's flaky code search."""
    if time.monotonic() - _zip_cache["at"] < 600 and _zip_cache["files"]:
        return _zip_cache["files"]
    repo, err = _repo()
    if err:
        return _zip_cache["files"]
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=45)) as session:
            async with session.get(f"{_API}/repos/{repo}/zipball/{config.BASE_BRANCH}", headers=ops._gh_headers()) as resp:
                if resp.status >= 300:
                    return _zip_cache["files"]
                raw, too_big = await read_capped(resp, 30_000_000)
                if too_big:
                    return _zip_cache["files"]
    except Exception:
        return _zip_cache["files"]
    files = parse_zip(raw)
    if not files:
        return _zip_cache["files"]
    _zip_cache["at"], _zip_cache["files"] = time.monotonic(), files
    return files


def grep_files(files: dict[str, str], pattern: str, prefix: str = "", max_hits: int = 25) -> dict:
    """Case-insensitive regex (or plain text when the regex is invalid) over file texts; at most 4 hits per file."""
    pattern = (pattern or "").strip()[:120]
    if not pattern:
        return {"error": "empty query"}
    try:
        rx = re.compile(pattern, re.I)
    except re.error:
        rx = re.compile(re.escape(pattern), re.I)
    hits, scanned = [], 0
    for path in sorted(files):
        if prefix and not path.startswith(prefix):
            continue
        scanned += 1
        per_file = 0
        for number, line in enumerate(files[path].split("\n"), 1):
            if rx.search(line):
                hits.append({"path": path, "line": number, "text": redact(line.strip()[:200])})
                per_file += 1
                if per_file >= 4 or len(hits) >= max_hits:
                    break
        if len(hits) >= max_hits:
            break
    return {"hits": hits, "files_scanned": scanned, **({"hint": "ничего не найдено: попробуй другое слово или часть имени"} if not hits else {})}


async def grep(pattern: str, prefix: str = "") -> dict:
    files = await _repo_files()
    if not files:
        return await search(pattern)  # zip unavailable: fall back to GitHub code search
    return grep_files(files, pattern, prefix.strip().lstrip("/"))
