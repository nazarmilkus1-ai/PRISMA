import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { safeApiError } from "@/lib/api-error";
import { STAFF_RPC } from "@prisma-eco/contracts";

const PERIODS = new Set(["24h", "7d", "30d", "all"]);
const KINDS = new Set(["applications", "chat", "audit"]);

function integerParam(value: string | null, fallback: number) {
  if (!value || !/^\d+$/.test(value)) return fallback;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : fallback;
}

export async function GET(request: Request) {
  const context = await requireAdminContext("analytics.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const url = new URL(request.url);
  const period = (url.searchParams.get("period") ?? "30d").toLowerCase();
  const kind = (url.searchParams.get("kind") ?? "chat").toLowerCase();
  const limit = Math.max(1, Math.min(100, integerParam(url.searchParams.get("limit"), 50)));
  const offset = Math.max(0, Math.min(1_000_000, integerParam(url.searchParams.get("offset"), 0)));

  if (!PERIODS.has(period)) return NextResponse.json({ error: "Некорректный период." }, { status: 400 });
  if (!KINDS.has(kind)) return NextResponse.json({ error: "Некорректный тип записей." }, { status: 400 });

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.analyticsDetails, {
    p_period: period,
    p_kind: kind,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) {
    return NextResponse.json(
      { error: safeApiError(error, "Не удалось загрузить подробные записи.") },
      { status: 409 },
    );
  }

  return NextResponse.json(data);
}
