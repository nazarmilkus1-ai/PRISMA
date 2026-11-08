import { NextRequest, NextResponse } from "next/server";
import { timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { consumeAuthRateLimit } from "@/lib/rate-limit";

const BodySchema = z.object({
  sessionToken: z.string().min(10),
  code: z.string().trim().regex(/^\d{6}$/, "Код повинен складатися з 6 цифр."),
});

const MAX_ATTEMPTS = 5;

function safeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  return bufA.length === bufB.length && timingSafeEqual(
    bufA as unknown as Uint8Array<ArrayBuffer>,
    bufB as unknown as Uint8Array<ArrayBuffer>,
  );
}

function bootstrapAdminIds() {
  return new Set(
    (process.env.ADMIN_TELEGRAM_IDS ?? "")
      .split(/[,\s]+/)
      .map((value) => value.trim())
      .filter(Boolean),
  );
}

export async function POST(request: NextRequest) {
  const parsed = BodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid_code" }, { status: 400 });
  const { sessionToken, code } = parsed.data;
  const client = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const [ipAllowed, sessionAllowed] = await Promise.all([
    consumeAuthRateLimit("telegram-verify-ip:" + client, 15, 600),
    consumeAuthRateLimit("telegram-verify-session:" + sessionToken, 8, 600),
  ]);
  if (!ipAllowed || !sessionAllowed) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  const supabaseAdmin = createSupabaseAdminClient();
  const { data: row, error: fetchError } = await supabaseAdmin
    .from("login_codes")
    .select("*")
    .eq("session_token", sessionToken)
    .maybeSingle();

  if (fetchError || !row) return NextResponse.json({ error: "login_expired" }, { status: 400 });
  if (row.status === "verified" || row.status === "expired" || new Date(row.expires_at).getTime() < Date.now()) {
    return NextResponse.json({ error: "login_expired" }, { status: 400 });
  }
  if (row.status !== "sent" || !row.code || !row.telegram_id) {
    return NextResponse.json({ error: "code_not_ready" }, { status: 409 });
  }
  if (row.attempts >= MAX_ATTEMPTS) {
    await supabaseAdmin.from("login_codes").update({ status: "expired" }).eq("id", row.id);
    return NextResponse.json({ error: "login_expired" }, { status: 400 });
  }
  if (!safeEqual(row.code, code)) {
    await supabaseAdmin.from("login_codes").update({ attempts: row.attempts + 1 }).eq("id", row.id);
    return NextResponse.json({ error: "invalid_code" }, { status: 401 });
  }

  const telegramId = String(row.telegram_id);
  const bootstrapIds = bootstrapAdminIds();
  const { data: existingAdmin } = await supabaseAdmin
    .from("admins")
    .select("id, user_id, role_id, users!inner(telegram_id)")
    .eq("users.telegram_id", telegramId)
    .maybeSingle();

  if (!existingAdmin && !bootstrapIds.has(telegramId)) {
    await supabaseAdmin.from("login_codes").update({ status: "expired" }).eq("id", row.id);
    return NextResponse.json({ error: "not_an_admin" }, { status: 403 });
  }

  // Bootstrap an env-configured admin into the normalized registry once.
  // This keeps existing installations compatible while making admins/roles
  // the durable source of truth for subsequent requests.
  // Consume the verified code atomically before creating the Auth session.
  // A second concurrent request must lose the status='sent' claim.
  const { data: consumed, error: consumeError } = await supabaseAdmin
    .from("login_codes")
    .update({ status: "verified" })
    .eq("id", row.id)
    .eq("status", "sent")
    .eq("code", row.code)
    .select("id")
    .maybeSingle();

  if (consumeError || !consumed) {
    return NextResponse.json({ error: "login_expired" }, { status: 400 });
  }

  if (!existingAdmin && bootstrapIds.has(telegramId)) {
    let { data: profile } = await supabaseAdmin.from("users").select("id").eq("telegram_id", row.telegram_id).maybeSingle();
    if (!profile) {
      const { data: insertedProfile, error: profileError } = await supabaseAdmin
        .from("users")
        .insert({ telegram_id: row.telegram_id })
        .select("id")
        .single();
      if (profileError || !insertedProfile) {
        console.error("[auth/telegram/verify] bootstrap user failed", profileError);
        return NextResponse.json({ error: "auth_failed" }, { status: 500 });
      }
      profile = insertedProfile;
    }

    const { data: role } = await supabaseAdmin.from("roles").select("id").eq("name", "admin").maybeSingle();
    const { error: adminInsertError } = await supabaseAdmin.from("admins").insert({ user_id: profile.id, role_id: role?.id ?? null });
    if (adminInsertError && !String(adminInsertError.message).toLowerCase().includes("duplicate")) {
      console.error("[auth/telegram/verify] bootstrap admin failed", adminInsertError);
      return NextResponse.json({ error: "auth_failed" }, { status: 500 });
    }
  }

  const email = `tg-${telegramId}@admins.prisma.internal`;
  const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: { data: { telegram_id: row.telegram_id } },
  });

  if (linkError || !linkData?.properties?.hashed_token) {
    console.error("[auth/telegram/verify] generateLink failed", linkError);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  const supabase = await createSupabaseServerClient();
  const { data: otpData, error: verifyError } = await supabase.auth.verifyOtp({
    token_hash: linkData.properties.hashed_token,
    type: "email",
  });

  if (verifyError) {
    console.error("[auth/telegram/verify] verifyOtp failed", verifyError);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  const authId = otpData.user?.id;
  if (!authId) {
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  // Bind the verified Supabase Auth identity to the existing PRISMA profile.
  // Without this link staff_get_auth_context cannot resolve the admin record,
  // even though the Telegram account exists in public.admins.
  const { data: account, error: accountError } = await supabaseAdmin
    .from("users")
    .select("id, auth_user_id")
    .eq("telegram_id", row.telegram_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (accountError || !account) {
    console.error("[auth/telegram/verify] profile lookup failed", accountError);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  if (account.auth_user_id && account.auth_user_id !== authId) {
    console.error("[auth/telegram/verify] auth identity mismatch for Telegram ID", row.telegram_id);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  if (!account.auth_user_id) {
    const { data: bound, error: bindError } = await supabaseAdmin
      .from("users")
      .update({ auth_user_id: authId, updated_at: new Date().toISOString() })
      .eq("id", account.id)
      .is("auth_user_id", null)
      .select("id")
      .maybeSingle();

    if (bindError || !bound) {
      console.error("[auth/telegram/verify] profile bind failed", bindError);
      return NextResponse.json({ error: "auth_failed" }, { status: 500 });
    }
  }

  await supabaseAdmin.from("login_history").insert({
    user_id: account.id,
    telegram_id: row.telegram_id,
    auth_user_id: authId,
    method: "telegram_code",
    success: true,
  });

  return NextResponse.json({ ok: true });
}
