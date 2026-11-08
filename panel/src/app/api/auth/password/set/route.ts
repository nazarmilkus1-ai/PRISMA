import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { requireAdmin, requireAdminContext } from "@/lib/require-admin";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { audit } from "@/lib/audit";

const Schema = z.object({ password: z.string().min(8).max(128) });

export async function POST(request: Request) {
  const admin = await requireAdmin();
  const context = await requireAdminContext();
  if (!admin || !context) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const parsed = Schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "password must be 8-128 characters" }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось установить пароль.") }, { status: 500 });

  const telegramId = admin.email?.match(/^tg-(\d+)@admins\.prisma\.internal$/)?.[1] ?? null;
  await createSupabaseAdminClient().from("login_history").insert({
    user_id: context.userId,
    telegram_id: telegramId ? Number(telegramId) : null,
    auth_user_id: admin.id,
    method: "password_change",
    success: true,
  });
  await audit(admin, { action: "auth.password_change", resource: "auth", metadata: { method: "password_fallback" } });
  return NextResponse.json({ ok: true });
}
