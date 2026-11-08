import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { audit } from "@/lib/audit";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET() {
  const context = await requireAdminContext();
  if (!context) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const supabase = await createSupabaseServerClient();
  const { data: securitySnapshot, error: securityError } = await supabase.rpc(STAFF_RPC.authSecurity);
  const snapshot = (securitySnapshot ?? {}) as {
    profile?: Record<string, unknown> | null;
    role?: string | null;
    login_history?: unknown;
  };
  const telegramId = context.user.email?.match(/^tg-(\d+)@admins\.prisma\.internal$/)?.[1] ?? null;

  const [factorsResult, aalResult] = await Promise.all([
    supabase.auth.mfa.listFactors(),
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
  ]);

  return NextResponse.json({
    profile: snapshot.profile ?? null,
    role: snapshot.role ?? context.role,
    permissions: [...context.permissions].sort(),
    auth: {
      email: context.user.email,
      auth_user_id: context.user.id,
      telegram_id: telegramId ? Number(telegramId) : null,
      aal: aalResult.data?.currentLevel ?? "aal1",
      next_aal: aalResult.data?.nextLevel ?? null,
      factors: [
        ...(factorsResult.data?.totp ?? []).map((factor) => ({ id: factor.id, type: "TOTP", name: factor.friendly_name ?? "Authenticator", status: factor.status })),
        ...(factorsResult.data?.phone ?? []).map((factor) => ({ id: factor.id, type: "PHONE", name: factor.friendly_name ?? "Телефон", status: factor.status })),
      ],
    },
    login_history: Array.isArray(snapshot.login_history) ? snapshot.login_history : [],
    errors: {
      security: securityError?.message ?? null,
      factors: factorsResult.error?.message ?? null,
      aal: aalResult.error?.message ?? null,
    },
  });
}

export async function POST(request: Request) {
  const context = await requireAdminContext();
  if (!context) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  if (body?.action !== "revoke_other_sessions") return NextResponse.json({ error: "unknown action" }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signOut({ scope: "others" });
  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить настройки безопасности.") }, { status: 500 });

  await audit(context.user, {
    action: "auth.revoke_other_sessions",
    resource: "auth_session",
    metadata: { scope: "others" },
  });

  return NextResponse.json({ ok: true });
}
