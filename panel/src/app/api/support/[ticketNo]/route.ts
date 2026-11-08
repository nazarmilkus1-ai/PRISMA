import { NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { safeApiError } from "@/lib/api-error";
import { STAFF_RPC } from "@prisma-eco/contracts";
import { audit } from "@/lib/audit";

const ReplySchema = z.object({
  message: z.string().trim().min(1).max(4000),
  close: z.boolean().optional().default(false),
});

const StatusSchema = z.object({
  status: z.enum(["OPEN","IN_REVIEW","RESOLVED","CLOSED"]),
});

function getTicketNo(value: string) {
  const ticketNo = Number(value);
  return Number.isSafeInteger(ticketNo) && ticketNo > 0 ? ticketNo : null;
}

export async function GET(_request: Request, { params }: { params: Promise<{ ticketNo: string }> }) {
  const { ticketNo: raw } = await params;
  const ticketNo = getTicketNo(raw);
  if (ticketNo === null) return NextResponse.json({ error: "Некорректный номер тикета." }, { status: 400 });

  const context = await requireAdminContext("support.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.supportTicket, { p_ticket_no: ticketNo });
  if (error) {
    const status = /NOT_FOUND/i.test(error.message) ? 404 : 409;
    return NextResponse.json({ error: safeApiError(error, "Не удалось загрузить тикет.") }, { status });
  }
  return NextResponse.json(data);
}

export async function POST(request: Request, { params }: { params: Promise<{ ticketNo: string }> }) {
  const { ticketNo: raw } = await params;
  const ticketNo = getTicketNo(raw);
  if (ticketNo === null) return NextResponse.json({ error: "Некорректный номер тикета." }, { status: 400 });

  const context = await requireAdminContext("support.manage");
  if (!context) return NextResponse.json({ error: "Недостаточно прав." }, { status: 403 });

  const parsed = ReplySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Сообщение должно содержать от 1 до 4000 символов." }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.replySupport, {
    p_ticket_no: ticketNo,
    p_message: parsed.data.message,
    p_close: parsed.data.close,
  });
  if (error) {
    const status = /NOT_FOUND/i.test(error.message) ? 404 : 409;
    return NextResponse.json({ error: safeApiError(error, "Не удалось отправить ответ.") }, { status });
  }

  try {
    await audit(context.user, {
      actorUserId: context.userId,
      action: "support.reply",
      resource: "support_ticket",
      resourceId: String(ticketNo),
      metadata: { closed: parsed.data.close, messageLength: parsed.data.message.length },
    });
  } catch (auditError) {
    console.error("[support] audit failed", auditError);
  }

  return NextResponse.json(data);
}

export async function PATCH(request: Request, { params }: { params: Promise<{ ticketNo: string }> }) {
  const { ticketNo: raw } = await params;
  const ticketNo = getTicketNo(raw);
  if (ticketNo === null) return NextResponse.json({ error: "Некорректный номер тикета." }, { status: 400 });

  const context = await requireAdminContext("support.manage");
  if (!context) return NextResponse.json({ error: "Недостаточно прав." }, { status: 403 });

  const parsed = StatusSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Некорректный статус тикета." }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.setSupportStatus, {
    p_ticket_no: ticketNo,
    p_status: parsed.data.status,
  });
  if (error) {
    const status = /NOT_FOUND/i.test(error.message) ? 404 : 409;
    return NextResponse.json({ error: safeApiError(error, "Не удалось изменить статус тикета.") }, { status });
  }

  try {
    await audit(context.user, {
      actorUserId: context.userId,
      action: "support.status",
      resource: "support_ticket",
      resourceId: String(ticketNo),
      metadata: { status: parsed.data.status },
    });
  } catch (auditError) {
    console.error("[support] audit failed", auditError);
  }

  return NextResponse.json(data);
}
