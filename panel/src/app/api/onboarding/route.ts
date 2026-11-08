import { NextResponse } from "next/server";
import { z } from "zod";
import { safeApiError } from "@/lib/api-error";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_RPC } from "@prisma-eco/contracts";

const Schema = z.object({
  title: z.string().trim().min(1).max(200),
  body: z.string().trim().min(1).max(4000),
});

export async function POST(request: Request) {
  const context = await requireAdminContext("notification.send");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = Schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.onboardingBroadcast, {
    p_title: parsed.data.title,
    p_body: parsed.data.body,
  });

  if (error) {
    return NextResponse.json({ error: safeApiError(error, "Не удалось запустить рассылку.") }, { status: 409 });
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось запустить рассылку." }, { status: 500 });

  return NextResponse.json({ ok: true, result });
}
