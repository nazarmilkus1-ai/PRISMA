import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

const CreateSchema = z.object({
  question: z.string().trim().min(3).max(300),
  options: z.array(z.string().trim().min(1).max(100)).min(2).max(8),
  closesAt: z.string().datetime().optional().nullable(),
});

export async function POST(request: Request) {
  const context = await requireAdminContext("poll.create");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = CreateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const options = [...new Set(parsed.data.options.map((value) => value.trim()).filter(Boolean))];
  if (options.length < 2) return NextResponse.json({ error: "Нужно минимум 2 разных варианта ответа." }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.createPoll, {
    p_question: parsed.data.question.trim(),
    p_options: options,
    p_closes_at: parsed.data.closesAt ?? null,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось загрузить голосования.") }, { status: 409 });
  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось создать голосование." }, { status: 500 });

  return NextResponse.json({ ok: true, id: result.id }, { status: 201 });
}
