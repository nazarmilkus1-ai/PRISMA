"""Settings of the autonomous agent. Everything is overridable by environment variables."""
import os


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def _int(name: str, default: int) -> int:
    try:
        return int(_env(name) or default)
    except ValueError:
        return default


def _ids(name: str) -> set[int]:
    out: set[int] = set()
    for part in _env(name).replace(";", ",").split(","):
        part = part.strip()
        if part.lstrip("-").isdigit():
            out.add(int(part))
    return out


# The agent exists only here: https://t.me/c/4365081749/1469
CHAT_ID = _int("AGENT_CHAT_ID", -1004365081749)
THREAD_ID = _int("AGENT_THREAD_ID", 1469)

ENABLED = _env("AGENT_ENABLED", "1").lower() not in {"0", "false", "off", "no"}
CYCLE_SECONDS = max(120, _int("AGENT_CYCLE_SECONDS", 600))
REPORT_SECONDS = max(600, _int("AGENT_REPORT_SECONDS", 3600))
MAX_STEPS = _int("AGENT_MAX_STEPS", 24)
MAX_CALLS_PER_DAY = _int("AGENT_MAX_CALLS_PER_DAY", 2500)
MAX_COMMITS_PER_DAY = _int("AGENT_MAX_COMMITS_PER_DAY", 40)
MAX_SAYS_PER_CYCLE = 3
MAX_FILES_PER_COMMIT = 8
MAX_FILE_CHARS = 80_000
TOOL_RESULT_CHARS = 7000

BASE_BRANCH = _env("GITHUB_BASE_BRANCH") or "PRISMA"
BRANCH_PREFIX = "agent/"

# Only the owner (all permissions) and these extra Telegram ids may press the merge button.
MERGE_ADMIN_IDS = _ids("AGENT_MERGE_ADMIN_IDS")

# Paths the agent can never write, whatever it decides: CI, secrets and env templates.
WRITE_BLOCKED_PREFIXES = (".github/", "node_modules/", ".git/")
WRITE_BLOCKED_NAMES = ("render.env", "vercel.env")
# A PR touching these needs a human with database access, so the merge button refuses it.
MERGE_REFUSED_PREFIXES = ("supabase/migrations/",)
# Merging these is allowed but the card warns loudly.
SELF_PREFIXES = ("bot/services/agent/", "bot/handlers/agent_topic.py")

# Read-only documentation sites the agent may fetch (https, no redirects off this list).
WEB_ALLOWLIST = (
    "docs.papermc.io", "jd.papermc.io", "docs.python.org", "docs.aiogram.dev", "nextjs.org", "react.dev",
    "supabase.com", "developer.mozilla.org", "docs.github.com", "docs.render.com", "vercel.com",
    "typescriptlang.org", "wiki.vg", "minecraft.wiki", "docs.advntr.dev", "geysermc.org",
)
