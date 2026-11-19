import { NextResponse } from "next/server";
import { z } from "zod";
import { STAFF_GUARDIAN_RPC } from "@prisma-eco/contracts";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { safeApiError } from "@/lib/api-error";
import { executeProposal } from "@/lib/guardian";

export const dynamic = "force-dynamic";

const DecideSchema = z.object({ id: z.string().uuid(), approve: z.boolean() });

export async function GET() {
  const context = await requireAdminContext("ops.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_GUARDIAN_RPC.overview);
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось загрузить данные охранника.") }, { status: 409 });
  return NextResponse.json(data);
}

export async function POST(request: Request) {
  const context = await requireAdminContext("ops.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const parsed = DecideSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc(STAFF_GUARDIAN_RPC.decide, { p_id: parsed.data.id, p_approve: parsed.data.approve });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось сохранить решение.") }, { status: 409 });

  if (!parsed.data.approve) return NextResponse.json({ status: "rejected" });
  const exec = await executeProposal(parsed.data.id);
  return NextResponse.json({ status: exec.ok ? "executed" : "failed", result: exec.result });
}
