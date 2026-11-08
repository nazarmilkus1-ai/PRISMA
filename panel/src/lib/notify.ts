import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_RPC } from "@prisma-eco/contracts";

function getBotToken() {
  const token = process.env.BOT_TOKEN;
  if (!token) throw new Error("BOT_TOKEN is not configured in panel runtime");
  return token;
}

async function getCommunityChatId(): Promise<number> {
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.communityChatId);

  if (error) throw new Error(error.message);

  const chatId = Number(data);
  if (!Number.isSafeInteger(chatId) || chatId === 0) {
    throw new Error("PRISMA community chat id is not configured");
  }

  return chatId;
}

async function telegramRequest<T>(token: string, method: string, body: Record<string, unknown>): Promise<T> {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.ok) {
    throw new Error(data.description ?? `Telegram API ${response.status}`);
  }
  return data.result as T;
}

export async function createTelegramCommunityInviteLink(applicationNo?: number | null): Promise<string> {
  const token = getBotToken();
  const chatId = await getCommunityChatId();
  const result = await telegramRequest<{ invite_link?: string }>(token, "createChatInviteLink", {
    chat_id: chatId,
    name: applicationNo ? `PRISMA #${applicationNo}` : "PRISMA member",
    member_limit: 1,
    expire_date: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60,
  });

  if (!result.invite_link) {
    throw new Error("Telegram did not return an invite link");
  }

  return result.invite_link;
}

export async function notifyTelegram(
  chatId: number,
  text: string,
  meta: { kind?: string; title?: string; userId?: string | null; data?: Record<string, unknown> } = {},
): Promise<void> {
  const db = await createSupabaseServerClient();
  const { error } = await db.rpc(STAFF_RPC.enqueueNotification, {
    p_telegram_id: chatId,
    p_user_id: meta.userId ?? null,
    p_kind: meta.kind ?? "SYSTEM",
    p_title: meta.title ?? "PRISMA",
    p_body: text,
    p_data: meta.data ?? {},
  });

  if (error) {
    throw new Error(error.message);
  }
}
