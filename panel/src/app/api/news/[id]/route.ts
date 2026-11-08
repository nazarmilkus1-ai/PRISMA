import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_RPC } from "@prisma-eco/contracts";

const UpdateSchema = z.object({
  title: z.string().trim().min(2).max(200).optional(),
  body: z.string().trim().min(2).max(10000).optional(),
  kind: z.enum(["NEWS", "UPDATE"]).optional(),
  isPublished: z.boolean().optional(),
});

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await requireAdminContext("news.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = UpdateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  if (Object.keys(parsed.data).length === 0) {
    return NextResponse.json({ error: "nothing to update" }, { status: 400 });
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageNews, {
    p_action: "UPDATE",
    p_news_id: id,
    p_title: parsed.data.title ?? null,
    p_body: parsed.data.body ?? null,
    p_kind: parsed.data.kind ?? null,
    p_is_published: parsed.data.isPublished ?? null,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить новость.") }, { status: 409 });
  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось обновить новость." }, { status: 500 });

  return NextResponse.json({ ok: true, result });
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  void request;
  const { id } = await params;
  const context = await requireAdminContext("news.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageNews, {
    p_action: "ARCHIVE",
    p_news_id: id,
    p_title: null,
    p_body: null,
    p_kind: null,
    p_is_published: null,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось изменить новость.") }, { status: 409 });
  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось архивировать новость." }, { status: 500 });

  return NextResponse.json({ ok: true, archived: true, result });
}
