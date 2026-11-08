import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { safeApiError } from "@/lib/api-error";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(request: Request) {
  const context = await requireAdminContext("support.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const url = new URL(request.url);
  const query = (url.searchParams.get("q") ?? "").trim().slice(0, 100);
  if (query.length < 2) {
    return NextResponse.json({ players: [] });
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.searchSupportRecipients, {
    p_search: query,
    p_limit: 25,
  });
  if (error) {
    return NextResponse.json(
      { error: safeApiError(error, "Не удалось найти игрока.") },
      { status: 409 },
    );
  }

  return NextResponse.json({ players: Array.isArray(data) ? data : [] });
}
