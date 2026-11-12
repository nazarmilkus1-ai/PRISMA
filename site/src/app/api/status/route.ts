import { NextResponse } from "next/server";
import { getCommunityStatus } from "@/lib/data";

export const dynamic = "force-dynamic";

/** Machine-readable twin of /status for uptime monitors. Availability only, nothing private. */
export async function GET() {
  const status = await getCommunityStatus();
  const ok = status.database.ok && status.minecraft.online;
  return NextResponse.json({ ok, ...status }, { status: status.database.ok ? 200 : 503, headers: { "Cache-Control": "public, max-age=15" } });
}
