import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin("appeal.view");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.appeal, { p_appeal_id: id });

  if (error) {
    if (/APPEAL_NOT_FOUND/i.test(error.message)) return NextResponse.json({ error: "not found" }, { status: 404 });
    return NextResponse.json({ error: safeApiError(error, "Не удалось обработать апелляцию.") }, { status: 409 });
  }

  return NextResponse.json(data);
}

const BodySchema = z.object({
  action: z.enum(["REVIEW", "APPROVE", "REJECT"]),
  note: z.string().trim().max(5000).optional(),
});

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const parsed = BodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Некорректные данные." }, { status: 400 });

  const admin = await requireAdmin("appeal.manage");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageAppeal, {
    p_appeal_id: id,
    p_action: parsed.data.action,
    p_note: parsed.data.note || null,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 409 });

  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось обновить апелляцию." }, { status: 500 });

  return NextResponse.json({ ok: true, result });
}
