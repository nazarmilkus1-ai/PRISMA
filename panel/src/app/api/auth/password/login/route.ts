import { NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { consumeAuthRateLimit } from "@/lib/rate-limit";

const Schema = z.object({
  telegramId: z.string().trim().regex(/^\d+$/),
  password: z.string().min(8).max(128),
});

function emailForTelegramId(id: string) {
  return `tg-${id}@admins.prisma.internal`;
}

export async function POST(request: Request) {
  const parsed = Schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid_credentials" }, { status: 400 });

  const allowed = await consumeAuthRateLimit("password:" + parsed.data.telegramId, 8, 600);
  if (!allowed) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email: emailForTelegramId(parsed.data.telegramId), password: parsed.data.password });
  if (error || !data.user) {
    await createSupabaseAdminClient().from("login_history").insert({ telegram_id: Number(parsed.data.telegramId), method: "password", success: false });
    return NextResponse.json({ error: "invalid_credentials" }, { status: 401 });
  }

  const { data: adminEntry } = await createSupabaseAdminClient()
    .from("admins")
    .select("id, users!inner(telegram_id)")
    .eq("users.telegram_id", Number(parsed.data.telegramId))
    .maybeSingle();

  const configured = (process.env.ADMIN_TELEGRAM_IDS ?? "").split(/[,\s]+/).filter(Boolean).includes(parsed.data.telegramId);
  if (!adminEntry && !configured) {
    await supabase.auth.signOut();
    await createSupabaseAdminClient().from("login_history").insert({ auth_user_id: data.user.id, telegram_id: Number(parsed.data.telegramId), method: "password", success: false });
    return NextResponse.json({ error: "not_an_admin" }, { status: 403 });
  }

  await createSupabaseAdminClient().from("login_history").insert({ auth_user_id: data.user.id, telegram_id: Number(parsed.data.telegramId), method: "password", success: true });
  return NextResponse.json({ ok: true });
}
