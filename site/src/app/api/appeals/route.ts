import { isPublicModuleEnabled } from "@/lib/modules";
import { NextResponse } from "next/server";
import { z } from "zod";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_APPEAL_MUTATION_RPC } from "@prisma-eco/contracts";

const Schema = z.object({
  punishment_id: z.string().uuid().optional().or(z.literal("")),
  reason: z.string().trim().min(10).max(2000),
});

export async function POST(request: Request) {
  if (!(await isPublicModuleEnabled("appeals"))) {
    return NextResponse.redirect(new URL("/app?error=module_disabled&module=appeals", request.url), 303);
  }
  const user = await getCurrentUser();
  if (!user) return NextResponse.redirect(new URL("/login", request.url), 303);

  const form = await request.formData();
  const parsed = Schema.safeParse({
    punishment_id: String(form.get("punishment_id") ?? ""),
    reason: String(form.get("reason") ?? ""),
  });

  if (!parsed.success) {
    return NextResponse.redirect(new URL("/app/appeals?error=invalid", request.url), 303);
  }

  const db = await createSupabaseServerClient();
  const { error } = await db.rpc(PARTICIPANT_APPEAL_MUTATION_RPC.create, {
    p_punishment_id: parsed.data.punishment_id || null,
    p_reason: parsed.data.reason,
  });

  const url = new URL("/app/appeals", request.url);
  if (error) url.searchParams.set("error", "Не удалось загрузить апелляции.");
  else url.searchParams.set("created", "1");
  return NextResponse.redirect(url, 303);
}
