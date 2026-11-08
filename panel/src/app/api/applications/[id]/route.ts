import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin, requireAdminContext } from "@/lib/require-admin";
import { z } from "zod";
import { STAFF_RPC } from "@prisma-eco/contracts";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin("application.view");
  if (!admin) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.application, { p_application_id: id });

  if (error) {
    if (/APPLICATION_NOT_FOUND/i.test(error.message)) {
      return NextResponse.json({ error: "not found" }, { status: 404 });
    }
    return NextResponse.json({ error: safeApiError(error, "Не удалось обработать заявку.") }, { status: 409 });
  }

  return NextResponse.json(data);
}

const BodySchema = z.object({
  action: z.enum(["approve", "reject"]),
  reason: z.string().trim().max(500).optional(),
});

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const parsed = BodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: "Некорректные данные запроса." }, { status: 400 });
  }

  const { action, reason } = parsed.data;
  const adminContext = await requireAdminContext(
    action === "approve" ? "application.approve" : "application.reject",
  );
  if (!adminContext) return NextResponse.json({ error: "Нет права выполнить действие." }, { status: 403 });

  const userClient = await createSupabaseServerClient();
  const rpc = await userClient.rpc(STAFF_RPC.decideApplication, {
    p_application_id: id,
    p_action: action,
    p_reason: action === "reject" ? reason || null : null,
  });

  if (rpc.error) {
    const message = safeApiError(rpc.error, "Решение не выполнено.");
    const status = /STAFF_IDENTITY|permission|ADMIN_LACKS|NOT_FOUND/i.test(message) ? 403 : 409;
    return NextResponse.json({ error: message }, { status });
  }

  const result = Array.isArray(rpc.data) ? rpc.data[0] : rpc.data;
  if (!result || result.success !== true) {
    return NextResponse.json({ error: "Решение не выполнено." }, { status: 500 });
  }



  return NextResponse.json({ ok: true, result });
}
