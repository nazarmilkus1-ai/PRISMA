import { safeApiError } from "@/lib/api-error";
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

const RoleSchema = z.enum(["owner", "head_admin", "head_staff", "admin", "senior_moderator", "moderator", "helper", "developer", "builder", "game_designer", "media", "event_manager", "content_maker"]);
const TelegramIdSchema = z.string().trim().regex(/^\d+$/).transform(Number);

export async function GET() {
  const context = await requireAdminContext("admin.view_audit");
  if (!context) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.adminRegistry);

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить данные администратора.") }, { status: 409 });
  return NextResponse.json(data ?? { admins: [], roles: [], role_permissions: [], permissions: [] });
}

const CreateSchema = z.object({ telegramId: TelegramIdSchema, role: RoleSchema.default("moderator") });

export async function POST(request: NextRequest) {
  const context = await requireAdminContext("admin.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const parsed = CreateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageAdmin, { p_action:"CREATE", p_telegram_id:parsed.data.telegramId, p_role_name:parsed.data.role });
  if (error) return NextResponse.json({error:safeApiError(error, "Не удалось изменить данные администратора.")},{status:409});
  return NextResponse.json(data);
}

const PatchSchema = z.object({ id: z.string().uuid(), role: RoleSchema });

export async function PATCH(request: NextRequest) {
  const context = await requireAdminContext("admin.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const parsed = PatchSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageAdmin, { p_action:"UPDATE", p_admin_id:parsed.data.id, p_role_name:parsed.data.role });
  if (error) return NextResponse.json({error:safeApiError(error, "Не удалось изменить данные администратора.")},{status:409});
  return NextResponse.json(data);
}

const DeleteSchema = z.object({ id: z.string().uuid() });

export async function DELETE(request: NextRequest) {
  const context = await requireAdminContext("admin.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  const parsed = DeleteSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "invalid administrator id" }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageAdmin, { p_action:"DELETE", p_admin_id:parsed.data.id });
  if (error) return NextResponse.json({error:safeApiError(error, "Не удалось изменить данные администратора.")},{status:409});
  return NextResponse.json(data);
}
