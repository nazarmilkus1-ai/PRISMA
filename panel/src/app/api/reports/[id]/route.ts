import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";
import { audit } from "@/lib/audit";

const BodySchema = z.object({
  status: z.enum(["OPEN", "IN_REVIEW", "RESOLVED", "DISMISSED"]),
  internal_notes: z.string().trim().max(5000).optional(),
  assigned_to: z.string().uuid().nullable().optional(),
  involved_players: z.array(z.string().trim().min(1).max(32)).max(20).optional(),
});

function requiredPermission(status: z.infer<typeof BodySchema>["status"]) {
  if (status === "IN_REVIEW") return "report.assign";
  if (status === "DISMISSED") return "report.reject";
  return "report.resolve";
}

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await requireAdminContext("report.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.report, { p_report_id: id });

  if (error) {
    if (/REPORT_NOT_FOUND/i.test(error.message)) {
      return NextResponse.json({ error: "Репорт не найден." }, { status: 404 });
    }
    return NextResponse.json({ error: safeApiError(error, "Не удалось обработать репорт.") }, { status: 409 });
  }

  return NextResponse.json(data);
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const parsed = BodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: "Некорректные данные репорта." }, { status: 400 });
  }

  const context = await requireAdminContext(requiredPermission(parsed.data.status));
  if (!context) return NextResponse.json({ error: "Недостаточно прав." }, { status: 403 });

  const userClient = await createSupabaseServerClient();
  const before = await userClient.rpc(STAFF_RPC.report, { p_report_id: id });
  if (before.error) {
    if (/REPORT_NOT_FOUND/i.test(before.error.message)) {
      return NextResponse.json({ error: "Репорт не найден." }, { status: 404 });
    }
    return NextResponse.json({ error: safeApiError(before.error, "Не удалось обработать репорт.") }, { status: 409 });
  }

  const rpc = await userClient.rpc(STAFF_RPC.updateReport, {
    p_report_id: id,
    p_status: parsed.data.status,
    p_internal_notes: parsed.data.internal_notes ?? null,
    p_assigned_to: parsed.data.assigned_to ?? null,
    p_involved_players: parsed.data.involved_players ?? null,
  });

  if (rpc.error) {
    const code = safeApiError(rpc.error, "Не удалось обновить репорт.");
    const status = /permission|staff|assignee/i.test(code) ? 403 : 409;
    return NextResponse.json({ error: code }, { status });
  }

  const result = Array.isArray(rpc.data) ? rpc.data[0] : rpc.data;
  if (!result || result.success !== true) {
    return NextResponse.json({ error: "Не удалось обновить репорт." }, { status: 500 });
  }

  const beforeReport = before.data as { status?: string; assigned_to?: string | null } | null;
  try {
    await audit(context.user, {
      actorUserId: context.userId,
      action: "report.update",
      resource: "report",
      resourceId: id,
      metadata: {
        from: beforeReport?.status ?? null,
        to: parsed.data.status,
        assigned_to: result.assigned_to ?? beforeReport?.assigned_to ?? null,
      },
    });
  } catch (error) {
    console.error("[reports] audit failed", error);
  }

  return NextResponse.json({ ok: true, result });
}
