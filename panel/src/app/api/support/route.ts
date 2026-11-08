import { NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { safeApiError } from "@/lib/api-error";
import { audit } from "@/lib/audit";
import { STAFF_RPC } from "@prisma-eco/contracts";

const STATUS = new Set(["OPEN","IN_REVIEW","RESOLVED","CLOSED"]);
const CreateTicketSchema = z.object({
  user_id: z.string().uuid(),
  message: z.string().trim().min(1).max(4000),
});

export async function GET(request: Request) {
  const context = await requireAdminContext("support.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const url = new URL(request.url);
  const rawStatus = (url.searchParams.get("status") ?? "OPEN").toUpperCase();
  const status = rawStatus === "ALL" ? null : STATUS.has(rawStatus) ? rawStatus : "OPEN";

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.supportTickets, {
    p_status: status,
    p_limit: 500,
  });
  if (error) {
    return NextResponse.json(
      { error: safeApiError(error, "Не удалось загрузить обращения в поддержку.") },
      { status: 409 },
    );
  }

  return NextResponse.json({ tickets: Array.isArray(data) ? data : [] });
}

export async function POST(request: Request) {
  const context = await requireAdminContext("support.manage");
  if (!context) return NextResponse.json({ error: "Недостаточно прав." }, { status: 403 });

  const parsed = CreateTicketSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: "Выберите игрока и укажите сообщение до 4000 символов." }, { status: 400 });
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.createSupportTicket, {
    p_user_id: parsed.data.user_id,
    p_message: parsed.data.message,
  });
  if (error) {
    const code = error.message || "";
    const message = /PLAYER_TELEGRAM_UNAVAILABLE/i.test(code)
      ? "У этого пользователя нет доступного Telegram ID."
      : /PLAYER_NOT_FOUND/i.test(code)
        ? "Игрок не найден."
        : safeApiError(error, "Не удалось начать диалог с игроком.");
    return NextResponse.json({ error: message }, { status: 409 });
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result || result.success !== true) {
    return NextResponse.json({ error: "Не удалось создать обращение." }, { status: 500 });
  }

  await audit(context.user, {
    actorUserId: context.userId,
    action: "support.initiated",
    resource: "support_ticket",
    resourceId: String(result.ticket_no),
    metadata: { targetUserId: parsed.data.user_id, messageLength: parsed.data.message.length },
  });

  return NextResponse.json(result);
}
