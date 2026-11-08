import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { requireAdminContext, requireAdminContextForMfa } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { audit } from "@/lib/audit";

const EnrollSchema = z.object({ action: z.literal("enroll") });
const VerifySchema = z.object({ action: z.literal("verify"), factor_id: z.string().uuid(), challenge_id: z.string().uuid(), code: z.string().regex(/^\d{6}$/) });
const UnenrollSchema = z.object({ action: z.literal("unenroll"), factor_id: z.string().uuid() });

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const action = body?.action;
  const isMfaChallengeFlow = action === "challenge" || action === "verify";
  const context = isMfaChallengeFlow
    ? await requireAdminContextForMfa()
    : await requireAdminContext();
  if (!context) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  if (action === "challenge") {
    const supabase = await createSupabaseServerClient();
    const { data: aal, error: aalError } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aalError) return NextResponse.json({ error: safeApiError(aalError, "Не удалось проверить состояние 2FA.") }, { status: 500 });
    if (aal.currentLevel === "aal2") return NextResponse.json({ ok: true, already_verified: true });

    const { data: factors, error: factorsError } = await supabase.auth.mfa.listFactors();
    if (factorsError || !factors) {
      return NextResponse.json({ error: safeApiError(factorsError, "Не удалось получить фактор 2FA.") }, { status: 500 });
    }
    const factor = factors.totp.find((item) => item.status === "verified");
    if (!factor) {
      return NextResponse.json({ error: "Для аккаунта не найден подтверждённый фактор 2FA. Обратитесь к владельцу PRISMA." }, { status: 409 });
    }

    const challenge = await supabase.auth.mfa.challenge({ factorId: factor.id });
    if (challenge.error || !challenge.data) {
      return NextResponse.json({ error: safeApiError(challenge.error, "Не удалось запросить код 2FA.") }, { status: 500 });
    }
    return NextResponse.json({ factor_id: factor.id, challenge_id: challenge.data.id });
  }

  if (action === "enroll") {
    const parsed = EnrollSchema.safeParse(body);
    if (!parsed.success) return NextResponse.json({ error: "invalid action" }, { status: 400 });

    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: "totp",
      friendlyName: "PRISMA Admin Authenticator",
    });
    if (error || !data) return NextResponse.json({ error: safeApiError(error, "Не удалось начать настройку 2FA.") }, { status: 500 });

    const challenge = await supabase.auth.mfa.challenge({ factorId: data.id });
    if (challenge.error || !challenge.data) return NextResponse.json({ error: challenge.error?.message ?? "Не удалось создать проверку 2FA." }, { status: 500 });

    return NextResponse.json({
      factor_id: data.id,
      challenge_id: challenge.data.id,
      qr_code: data.totp?.qr_code ?? null,
      secret: data.totp?.secret ?? null,
      uri: data.totp?.uri ?? null,
    });
  }

  if (action === "verify") {
    const parsed = VerifySchema.safeParse(body);
    if (!parsed.success) return NextResponse.json({ error: "Код 2FA должен содержать 6 цифр." }, { status: 400 });

    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.mfa.verify({
      factorId: parsed.data.factor_id,
      challengeId: parsed.data.challenge_id,
      code: parsed.data.code,
    });
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить операцию 2FA.") }, { status: 400 });

    await audit(context.user, { action: "auth.mfa_enable", resource: "auth_mfa", resourceId: parsed.data.factor_id });
    return NextResponse.json({ ok: true });
  }

  if (action === "unenroll") {
    const parsed = UnenrollSchema.safeParse(body);
    if (!parsed.success) return NextResponse.json({ error: "invalid factor" }, { status: 400 });

    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.mfa.unenroll({ factorId: parsed.data.factor_id });
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить операцию 2FA.") }, { status: 400 });

    await audit(context.user, { action: "auth.mfa_disable", resource: "auth_mfa", resourceId: parsed.data.factor_id });
    return NextResponse.json({ ok: true });
  }

  return NextResponse.json({ error: "unknown action" }, { status: 400 });
}
