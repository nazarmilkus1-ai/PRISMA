import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_SUPPORT_RPC } from "@prisma-eco/contracts";

const Schema = z.object({
  message: z.string().trim().min(3).max(4000),
});

export async function GET() {
  await requireUser();
  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_SUPPORT_RPC.list, { p_limit: 50 });
  if (error) return NextResponse.json({ error: "Не удалось загрузить обращения." }, { status: 409 });
  return NextResponse.json({ tickets: Array.isArray(data) ? data : [] });
}

export async function POST(request: Request) {
  const user = await requireUser();
  if (user.is_banned) return NextResponse.json({ error: "Заблокированные пользователи не могут создавать обращения." }, { status: 403 });

  const parsed = Schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Сообщение должно содержать от 3 до 4000 символов." }, { status: 400 });

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(PARTICIPANT_SUPPORT_RPC.create, { p_message: parsed.data.message });
  if (error) {
    const code = error.message || "";
    const message = code === "INVALID_MESSAGE" ? "Сообщение должно содержать от 3 до 4000 символов." : code === "DAILY_LIMIT" ? "Лимит обращений на сегодня уже использован (2 обращения)." : "Не удалось создать обращение.";
    return NextResponse.json({ error: message }, { status: 409 });
  }
  return NextResponse.json(data);
}
