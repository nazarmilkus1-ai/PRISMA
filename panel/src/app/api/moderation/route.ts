import { safeApiError } from "@/lib/api-error";
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(request: NextRequest) {
  const admin = await requireAdmin("punishment.view_history");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const search = request.nextUrl.searchParams.get("search")?.trim() ?? "";
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.moderationSearchPlayers, {
    p_search: search,
    p_limit: search.length >= 2 ? 100 : 250,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить действие модерации.") }, { status: 409 });
  return NextResponse.json({ users: Array.isArray(data) ? data : [] });
}

const ActionSchema = z.object({
  userId: z.string().uuid(),
  type: z.enum(["WARN", "MUTE", "KICK", "BAN", "UNMUTE", "UNBAN", "WHITELIST", "UNWHITELIST"]),
  reason: z.string().trim().min(1).max(500),
  durationMinutes: z.number().int().positive().max(60 * 24 * 30).optional(),
});

export async function POST(request: Request) {
  const parsed = ActionSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { userId, type, reason, durationMinutes } = parsed.data;
  const permission = {
    WARN: "punishment.warn",
    MUTE: "punishment.mute",
    KICK: "punishment.kick",
    BAN: "punishment.ban",
    UNMUTE: "punishment.remove",
    UNBAN: "punishment.remove",
    WHITELIST: "application.approve",
    UNWHITELIST: "application.reject",
  }[type];

  const admin = await requireAdmin(permission);
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.applyModeration, {
    p_target_user_id: userId,
    p_type: type,
    p_reason: reason,
    p_duration_minutes: durationMinutes ?? null,
  });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить действие модерации.") }, { status: 409 });

  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) {
    return NextResponse.json({ error: "Не удалось применить действие." }, { status: 500 });
  }

  return NextResponse.json({ ok: true, result });
}
