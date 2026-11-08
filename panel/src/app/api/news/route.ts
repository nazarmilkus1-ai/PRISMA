import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_RPC } from "@prisma-eco/contracts";

const CreateSchema = z.object({
  title: z.string().trim().min(2).max(200),
  body: z.string().trim().min(2).max(10000),
  kind: z.enum(["NEWS", "UPDATE"]),
  isPublished: z.boolean().default(true),
});

export async function POST(request: Request) {
  const context = await requireAdminContext("news.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = CreateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.manageNews, {
    p_action: "CREATE",
    p_news_id: null,
    p_title: parsed.data.title,
    p_body: parsed.data.body,
    p_kind: parsed.data.kind,
    p_is_published: parsed.data.isPublished,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось загрузить новости.") }, { status: 409 });
  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.success) return NextResponse.json({ error: "Не удалось создать новость." }, { status: 500 });

  return NextResponse.json({ ok: true, id: result.id, result }, { status: 201 });
}
