import { NextResponse } from "next/server";
import { timingSafeEqual } from "node:crypto";
import { runTick } from "@/lib/guardian";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function sha(value: string) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

async function authorized(request: Request) {
  const secret = process.env.GUARDIAN_SECRET;
  if (!secret || secret.length < 16) return false;
  const given = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  return timingSafeEqual(await sha(given), await sha(secret));
}

export async function POST(request: Request) {
  if (!(await authorized(request))) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const result = await runTick();
  return NextResponse.json(result);
}
