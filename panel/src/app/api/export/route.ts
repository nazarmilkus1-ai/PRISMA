import { safeApiError } from "@/lib/api-error";
import { NextRequest, NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { requireAdminContext } from "@/lib/require-admin";

const RESOURCE = ["users", "applications", "moderation", "reports", "audit"] as const;
type Resource = (typeof RESOURCE)[number];

function csv(rows: Record<string, unknown>[]) {
  if (!rows.length) return "empty\n";
  const keys = Array.from(new Set(rows.flatMap(row => Object.keys(row))));
  const esc = (v: unknown) => { const s = v == null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v); return '"' + s.replace(/"/g, '""') + '"'; };
  return [keys.map(esc).join(","), ...rows.map(row => keys.map(k => esc(row[k])).join(","))].join("\n");
}

export async function GET(request: NextRequest) {
  const resource = request.nextUrl.searchParams.get("resource") as Resource | null;
  if (!resource || !RESOURCE.includes(resource)) return NextResponse.json({ error: "unknown resource" }, { status: 400 });

  const permission = resource === "users" ? "player.view" : resource === "applications" ? "application.view" : resource === "moderation" ? "punishment.view_history" : resource === "reports" ? "report.view" : "admin.view_audit";
  const context = await requireAdminContext(permission);
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const db = createSupabaseAdminClient();
  let rows: Record<string, unknown>[] = [];
  if (resource === "users") {
    const { data, error } = await db.from("player_360").select("*").order("created_at", { ascending: false }).limit(5000);
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить экспорт.") }, { status: 500 });
    rows = (data ?? []) as Record<string, unknown>[];
  } else if (resource === "applications") {
    const { data, error } = await db.from("applications").select("id,user_id,full_name,age,nickname,platform,discovery_source,status,rejection_reason,birth_date,goal,about,reviewed_by_tg_id,reviewed_by_name,reviewed_at,created_at").order("created_at", { ascending: false }).limit(5000);
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить экспорт.") }, { status: 500 });
    rows = (data ?? []) as Record<string, unknown>[];
  } else if (resource === "moderation") {
    const { data, error } = await db.from("moderation_logs").select("id,target_id,type,reason,duration_minutes,expires_at,source,issued_by_tg_id,issued_by_name,revoked,revoked_at,revoked_by_name,created_at").order("created_at", { ascending: false }).limit(5000);
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить экспорт.") }, { status: 500 });
    rows = (data ?? []) as Record<string, unknown>[];
  } else if (resource === "reports") {
    const { data, error } = await db.from("reports").select("id,ticket_no,user_id,type,target_nickname,description,status,priority,category,assigned_to,evidence,involved_players,coordinates,occurred_at,resolved_at,internal_notes,sla_due_at,source_type,source_id,created_at,updated_at").order("created_at", { ascending: false }).limit(5000);
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить экспорт.") }, { status: 500 });
    rows = (data ?? []) as Record<string, unknown>[];
  } else {
    const { data, error } = await db.from("audit_logs").select("id,actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data,request_id,correlation_id,ip_address,created_at").order("created_at", { ascending: false }).limit(5000);
    if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось выполнить экспорт.") }, { status: 500 });
    rows = (data ?? []) as Record<string, unknown>[];
  }

  const body = csv(rows);
  return new NextResponse("\uFEFF" + body, {
    status: 200,
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="prisma-${resource}-export-${new Date().toISOString().slice(0,10)}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
