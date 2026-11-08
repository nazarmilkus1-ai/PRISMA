import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

const PatchSchema = z.object({ isActive: z.boolean() });

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await requireAdminContext("poll.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = PatchSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid body" }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.managePoll, {
    p_poll_id: id,
    p_is_active: parsed.data.isActive,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить голосование.") }, { status: 409 });
  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось изменить статус голосования." }, { status: 500 });

  return NextResponse.json({ ok: true, result });
}
