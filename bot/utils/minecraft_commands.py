import json
from html import escape
from pathlib import Path
from typing import Any

CATALOG_PATH = Path(__file__).resolve().parents[2] / "packages" / "contracts" / "minecraft-commands.json"


def load_catalog() -> dict[str, Any]:
    with CATALOG_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


ACCESS_LABELS = {
    "APPROVED": "участник",
    "CLAN_MEMBER": "участник клана",
    "CLAN_OFFICER": "офицер/выше",
    "CLAN_OWNER": "владелец/выше",
    "STAFF": "персонал",
}


def render_catalog(platform: str | None = None) -> str:
    catalog = load_catalog()
    platform = (platform or "").upper()

    lines = ["🧭 <b>Команды Minecraft PRISMA</b>", ""]
    for item in catalog["commands"]:
        command = escape(item["command"])
        aliases = item.get("aliases") or []
        alias_text = f" <code>({escape(', '.join(aliases))})</code>" if aliases else ""
        access = ACCESS_LABELS.get(item["access"], item["access"])
        lines.append(f"• <code>{command}</code>{alias_text} — {escape(item['description'])} <i>[{escape(access)}]</i>")
        for subcommand, description, subaccess in item.get("subcommands", []):
            lines.append(
                f"  └ <code>{command} {escape(subcommand)}</code> — "
                f"{escape(description)} <i>[{escape(ACCESS_LABELS.get(subaccess, subaccess))}]</i>"
            )

    lines.append("")
    lines.append("<b>Войны кланов:</b>")
    for subcommand, description, subaccess in catalog["clan_war_subcommands"]:
        lines.append(
            f"• <code>/clan war {escape(subcommand)}</code> — {escape(description)} "
            f"<i>[{escape(ACCESS_LABELS.get(subaccess, subaccess))}]</i>"
        )

    auth = next((x for x in catalog["authentication"] if x["platform"] == platform), None)
    if auth:
        lines.extend(["", f"<b>Авторизация {escape(auth['name'])}:</b>", escape(auth["description"])])
        for command, description in auth.get("commands", []):
            lines.append(f"• <code>{escape(command)}</code> — {escape(description)}")
    elif platform == "BEDROCK":
        lines.extend(["", "<b>Bedrock:</b>", "Geyser + Floodgate. Отдельный пароль PRISMA Auth для Bedrock не требуется."])
    else:
        lines.extend(["", "<b>Авторизация:</b>", "Java — PRISMA Auth; Bedrock — Geyser/Floodgate."])

    return "\n".join(lines)
