import { NextResponse } from "next/server";
import { z } from "zod";
import { requireAdminContext } from "@/lib/require-admin";

const Schema = z.object({ chat_id: z.coerce.bigint() });

async function telegram(method: string, body?: Record<string, unknown>) {
  const token = process.env.BOT_TOKEN;
  if (!token) return { ok: false, error: "BOT_TOKEN не налаштований у panel runtime." };
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}), cache: "no-store",
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.ok) return { ok: false, error: data.description ?? `Telegram API ${response.status}` };
  return { ok: true, data: data.result };
}

export async function POST(request: Request) {
  const context = await requireAdminContext("settings.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const parsed = Schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid chat id" }, { status: 400 });

  const bot = await telegram("getMe");
  if (!bot.ok) return NextResponse.json({ ok: false, stage: "bot", error: bot.error }, { status: 503 });

  const chat = await telegram("getChat", { chat_id: parsed.data.chat_id.toString() });
  if (!chat.ok) return NextResponse.json({ ok: false, stage: "chat", bot: bot.data, error: chat.error }, { status: 404 });

  const member = await telegram("getChatMember", { chat_id: parsed.data.chat_id.toString(), user_id: bot.data.id });
  if (!member.ok) return NextResponse.json({ ok: false, stage: "permissions", bot: bot.data, chat: chat.data, error: member.error }, { status: 403 });

  const isAdmin = member.data.status === "administrator" || member.data.status === "creator";
  return NextResponse.json({
    ok: true,
    bot: { id: bot.data.id, username: bot.data.username, name: bot.data.first_name },
    chat: { id: chat.data.id, title: chat.data.title, type: chat.data.type },
    membership: { status: member.data.status, can_delete_messages: member.data.can_delete_messages ?? false, can_restrict_members: member.data.can_restrict_members ?? false, can_invite_users: member.data.can_invite_users ?? false },
    is_admin: isAdmin,
  });
}
