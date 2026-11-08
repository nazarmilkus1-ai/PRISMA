import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(_request: Request, { params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;
  const admin = await requireAdmin("punishment.view_history");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.moderationPlayer, {
    p_user_id: userId,
  });

  if (error) {
    if (/USER_NOT_FOUND/i.test(error.message)) {
      return NextResponse.json({ error: "not found" }, { status: 404 });
    }
    return NextResponse.json({ error: safeApiError(error, "Не удалось применить действие модерации.") }, { status: 409 });
  }

  return NextResponse.json(data ?? { user: null, logs: [] });
}
