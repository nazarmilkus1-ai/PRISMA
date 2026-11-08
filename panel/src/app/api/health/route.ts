import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET() {
  const publicSupabaseKey =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  const checks = {
    supabase: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && publicSupabaseKey),
    serviceRole: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    adminAllowlist: Boolean(process.env.ADMIN_EMAILS || process.env.ADMIN_TELEGRAM_IDS),
    telegramBot: Boolean(process.env.NEXT_PUBLIC_BOT_USERNAME),
    // Used as deployment metadata, but does not block authentication or DB access.
    siteUrl: Boolean(process.env.NEXT_PUBLIC_SITE_URL),
  };

  // NEXT_PUBLIC_SITE_URL is documented as recommended, not required.
  // Telegram login does require the bot username to build the deep link.
  const ready = checks.supabase && checks.serviceRole && checks.adminAllowlist && checks.telegramBot;

  return NextResponse.json(
    {
      service: "prisma-panel",
      status: ready ? "ok" : "degraded",
      checks,
      timestamp: new Date().toISOString(),
    },
    {
      status: ready ? 200 : 503,
      headers: { "Cache-Control": "no-store" },
    },
  );
}
