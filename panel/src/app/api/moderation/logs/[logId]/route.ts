import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function POST(request: Request, { params }: { params: Promise<{ logId: string }> }) {
  const { logId } = await params;
  const admin = await requireAdmin("punishment.remove");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.revokeModeration, { p_log_id: logId });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить запись модерации.") }, { status: 409 });

  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) {
    return NextResponse.json({ error: "Не удалось снять наказание." }, { status: 500 });
  }

  return NextResponse.json({ ok: true, result });
}
