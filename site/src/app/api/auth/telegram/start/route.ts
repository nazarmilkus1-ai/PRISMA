import { NextResponse } from "next/server";
import { randomBytes } from "node:crypto";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { consumeAuthRateLimit } from "@/lib/rate-limit";

const TTL_MINUTES = 5;

export async function POST(request: Request) {
  const client = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  if (!(await consumeAuthRateLimit("site-telegram-start:" + client, 12, 600))) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const botUsername = process.env.NEXT_PUBLIC_BOT_USERNAME;
  if (!botUsername) return NextResponse.json({ error: "server_misconfigured" }, { status: 500 });

  const admin = createSupabaseAdminClient();

  // Keep abandoned login attempts from accumulating forever, while preserving
  // verified rows for audit history.
  const { error: cleanupError } = await admin
    .from("login_codes")
    .delete()
    .in("status", ["pending", "sent"])
    .lt("expires_at", new Date().toISOString());

  if (cleanupError) {
    console.warn("[site/auth/start] cleanup expired login codes", cleanupError);
  }

  const sessionToken = randomBytes(24).toString("base64url");
  const expiresAt = new Date(Date.now() + TTL_MINUTES * 60_000).toISOString();

  const { error } = await admin.from("login_codes").insert({
    session_token: sessionToken,
    status: "pending",
    expires_at: expiresAt,
  });

  if (error) {
    console.error("[site/auth/start]", error);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  return NextResponse.json({
    sessionToken,
    botDeepLink: `https://t.me/${botUsername}?start=${sessionToken}`,
    expiresInSeconds: TTL_MINUTES * 60,
  });
}
