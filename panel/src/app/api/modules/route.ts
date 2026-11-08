import { NextResponse } from "next/server";
import { z } from "zod";
import { MODULE_IDS, STAFF_MODULE_RPC } from "@prisma-eco/contracts";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { safeApiError } from "@/lib/api-error";

const UpdateSchema = z.object({
  module_id: z.enum(MODULE_IDS),
  enabled: z.boolean(),
  reason: z.string().trim().max(500).nullable().optional(),
}).refine((value) => value.enabled || Boolean(value.reason?.trim()), {
  path: ["reason"],
  message: "Укажите причину отключения.",
});

export async function GET() {
  const context = await requireAdminContext("modules.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_MODULE_RPC.list);

  if (error) {
    return NextResponse.json(
      { error: safeApiError(error, "Не удалось загрузить состояние модулей.") },
      { status: 409 },
    );
  }

  return NextResponse.json({ modules: Array.isArray(data) ? data : [] });
}

export async function POST(request: Request) {
  const context = await requireAdminContext("modules.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = UpdateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_MODULE_RPC.set, {
    p_module_id: parsed.data.module_id,
    p_enabled: parsed.data.enabled,
    p_reason: parsed.data.reason ?? null,
  });

  if (error) {
    return NextResponse.json(
      { error: safeApiError(error, "Не удалось изменить состояние модуля.") },
      { status: 409 },
    );
  }

  return NextResponse.json(data);
}
