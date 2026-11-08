import { NextRequest, NextResponse } from "next/server";
import { timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { consumeAuthRateLimit } from "@/lib/rate-limit";

const BodySchema = z.object({
  sessionToken: z.string().min(10).max(200),
  code: z.string().trim().regex(/^\d{6}$/),
});

const MAX_ATTEMPTS = 5;

function safeEqual(a: string, b: string) {
  const aa = new Uint8Array(Buffer.from(a));
  const bb = new Uint8Array(Buffer.from(b));
  return aa.length === bb.length && timingSafeEqual(aa as Uint8Array<ArrayBuffer>, bb as Uint8Array<ArrayBuffer>);
}

export async function POST(request: NextRequest) {
  const parsed = BodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid_code" }, { status: 400 });

  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  const { sessionToken, code } = parsed.data;
  const [ipAllowed, sessionAllowed] = await Promise.all([
    consumeAuthRateLimit("site-telegram-verify-ip:" + ip, 15, 600),
    consumeAuthRateLimit("site-telegram-verify-session:" + sessionToken, 8, 600),
  ]);
  if (!ipAllowed || !sessionAllowed) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const admin = createSupabaseAdminClient();

  const { data: row, error: fetchError } = await admin
    .from("login_codes")
    .select("id,status,code,telegram_id,expires_at,attempts")
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
    await admin.from("login_codes").update({ status: "expired" }).eq("id", row.id).eq("status", "sent");
    return NextResponse.json({ error: "login_expired" }, { status: 400 });
  }

  if (!safeEqual(String(row.code), code)) {
    await admin
      .from("login_codes")
      .update({ attempts: row.attempts + 1 })
      .eq("id", row.id)
      .eq("status", "sent")
      .eq("attempts", row.attempts);
    return NextResponse.json({ error: "invalid_code" }, { status: 401 });
  }

  const { data: account, error: accountError } = await admin
    .from("users")
    .select("id,auth_user_id,telegram_id")
    .eq("telegram_id", row.telegram_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (accountError || !account) {
    await admin.from("login_codes").update({ status: "expired" }).eq("id", row.id).eq("status", "sent");
    return NextResponse.json({ error: "not_registered" }, { status: 403 });
  }

  // Atomically consume the code before creating the Auth session.
  // This prevents two concurrent requests from reusing the same valid code.
  const { data: consumed, error: consumeError } = await admin
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

  const email = `tg-${String(row.telegram_id)}@admins.prisma.internal`;
  const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: { data: { telegram_id: row.telegram_id } },
  });

  if (linkError || !linkData?.properties?.hashed_token) {
    console.error("[site/auth/verify] generateLink", linkError);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  const supabase = await createSupabaseServerClient();
  const { data: otpData, error: verifyError } = await supabase.auth.verifyOtp({
    token_hash: linkData.properties.hashed_token,
    type: "email",
  });

  if (verifyError) {
    console.error("[site/auth/verify] verifyOtp", verifyError);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  const authId = otpData.user?.id;
  if (!authId) return NextResponse.json({ error: "auth_failed" }, { status: 500 });

  if (account.auth_user_id && account.auth_user_id !== authId) {
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  if (!account.auth_user_id) {
    const { error: bindError } = await admin
      .from("users")
      .update({ auth_user_id: authId, updated_at: new Date().toISOString() })
      .eq("id", account.id)
      .is("auth_user_id", null);

    if (bindError) {
      console.error("[site/auth/verify] bind user", bindError);
      return NextResponse.json({ error: "auth_failed" }, { status: 500 });
    }
  }

  await admin.from("login_history").insert({
    user_id: account.id,
    telegram_id: row.telegram_id,
    auth_user_id: authId,
    method: "telegram_code_participant",
    success: true,
  });

  return NextResponse.json({ ok: true });
}
