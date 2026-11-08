import { safeApiError } from "@/lib/api-error";
import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(request: NextRequest) {
  const admin = await requireAdmin("appeal.view");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const status = request.nextUrl.searchParams.get("status")?.trim() || "OPEN";
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.appeals, {
    p_status: status,
    p_limit: 500,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось загрузить апелляции.") }, { status: 409 });
  return NextResponse.json({ appeals: Array.isArray(data) ? data : [] });
}
