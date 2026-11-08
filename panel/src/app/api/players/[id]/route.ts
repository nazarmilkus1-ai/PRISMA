import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_MINECRAFT_AUTH_RPC, STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin("player.view");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const [{ data, error }, { data: minecraftAuth, error: authError }] = await Promise.all([
    supabase.rpc(STAFF_RPC.player360, { p_user_id: id }),
    supabase.rpc(STAFF_MINECRAFT_AUTH_RPC.status, { p_user_id: id }),
  ]);

  if (error) {
    if (/PLAYER_NOT_FOUND/i.test(error.message)) {
      return NextResponse.json({ error: "player not found" }, { status: 404 });
    }
    return NextResponse.json({ error: safeApiError(error, "Не удалось изменить данные игрока.") }, { status: 409 });
  }

  if (authError) {
    return NextResponse.json({ error: safeApiError(authError, "Не удалось загрузить статус PRISMA Auth.") }, { status: 409 });
  }

  return NextResponse.json({ ...data, minecraft_auth: minecraftAuth });
}
