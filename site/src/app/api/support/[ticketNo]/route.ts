import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_SUPPORT_RPC } from "@prisma-eco/contracts";

const Schema = z.object({
  message: z.string().trim().min(1).max(4000),
});

function parseTicketNo(value: string) {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

export async function GET(_request: Request, { params }: { params: Promise<{ ticketNo: string }> }) {
  await requireUser();
  const ticketNo = parseTicketNo((await params).ticketNo);
  if (ticketNo === null) return NextResponse.json({ error: "Некорректный номер тикета." }, { status: 400 });

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_SUPPORT_RPC.get, { p_ticket_no: ticketNo });
  if (error) return NextResponse.json({ error: "Обращение не найдено." }, { status: 404 });
  return NextResponse.json(data);
}

export async function POST(request: Request, { params }: { params: Promise<{ ticketNo: string }> }) {
  const user = await requireUser();
  if (user.is_banned) return NextResponse.json({ error: "Заблокированные пользователи не могут писать в поддержку." }, { status: 403 });

  const ticketNo = parseTicketNo((await params).ticketNo);
  if (ticketNo === null) return NextResponse.json({ error: "Некорректный номер тикета." }, { status: 400 });

  const parsed = Schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Сообщение должно содержать от 1 до 4000 символов." }, { status: 400 });

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_SUPPORT_RPC.reply, {
    p_ticket_no: ticketNo,
    p_message: parsed.data.message,
  });
  if (error) {
    const message =
      error.message === "SUPPORT_TICKET_CLOSED"
        ? "Это обращение уже закрыто. Создайте новое обращение, если проблема осталась."
        : "Не удалось отправить сообщение.";
    return NextResponse.json({ error: message }, { status: 409 });
  }
  return NextResponse.json(data);
}
