import { NextResponse } from "next/server";
import { randomBytes } from "node:crypto";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { consumeAuthRateLimit } from "@/lib/rate-limit";

// Единственный способ входа в панель: пользователь жмёт «Войти», открывает
// бота по диплинку, бот присылает 6-значный код, пользователь вставляет его
// в панель. Никаких других способов входа быть не должно (см. verify/route.ts,
// page.tsx) — этот файл только заводит "сессию входа" (session_token) и
// отдаёт диплинк на бота, сам код ещё не создан.

const CODE_TTL_MINUTES = 5;

export async function POST(request: Request) {
  const client = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (!(await consumeAuthRateLimit("telegram-start:" + client, 12, 600))) return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  const botUsername = process.env.NEXT_PUBLIC_BOT_USERNAME;
  if (!botUsername) {
    return NextResponse.json({ error: "server_misconfigured" }, { status: 500 });
  }

  const sessionToken = randomBytes(24).toString("base64url");
  const expiresAt = new Date(Date.now() + CODE_TTL_MINUTES * 60_000).toISOString();

  const supabaseAdmin = createSupabaseAdminClient();
  const { error } = await supabaseAdmin.from("login_codes").insert({
    session_token: sessionToken,
    status: "pending",
    expires_at: expiresAt,
  });

  if (error) {
    console.error("[auth/telegram/start] insert failed", error);
    return NextResponse.json({ error: "auth_failed" }, { status: 500 });
  }

  return NextResponse.json({
    sessionToken,
    botDeepLink: `https://t.me/${botUsername}?start=${sessionToken}`,
    expiresInSeconds: CODE_TTL_MINUTES * 60,
  });
}
