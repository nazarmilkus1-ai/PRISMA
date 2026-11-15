import { NextResponse } from "next/server";
import { safeApiError } from "@/lib/api-error";
import { z } from "zod";
import { requireAdminContext } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { STAFF_RPC } from "@prisma-eco/contracts";


const CreateSchema = z.object({
  slug: z.string().trim().min(1).max(120).regex(/^[a-z0-9-]+$/),
  title: z.string().trim().min(2).max(200),
  excerpt: z.string().trim().max(500).optional().nullable(),
  content: z.string().trim().min(1),
  category: z.string().trim().min(1).max(50),
  published: z.boolean().default(false),
  visibility: z.enum(["PUBLIC", "MEMBER", "STAFF"]).default("PUBLIC"),
});

const UpdateSchema = CreateSchema.partial().omit({ slug: true });

export async function GET() {
  const context = await requireAdminContext("wiki.view");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("wiki_pages").select("*").order("updated_at", { ascending: false });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось загрузить страницы Wiki.") }, { status: 409 });

  return NextResponse.json({ pages: data ?? [] });
}

export async function POST(request: Request) {
  const context = await requireAdminContext("wiki.manage");
  if (!context) return NextResponse.json({ error: "forbidden" }, { status: 403 });

  const parsed = CreateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data: raw, error } = await supabase.rpc(STAFF_RPC.manageWiki, {
    p_action: "CREATE",
    p_page_id: null,
    p_slug: parsed.data.slug,
    p_title: parsed.data.title,
    p_excerpt: parsed.data.excerpt ?? null,
    p_content: parsed.data.content,
    p_category: parsed.data.category,
    p_published: parsed.data.published,
    p_visibility: parsed.data.visibility,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, "Не удалось создать страницу Wiki.") }, { status: 409 });
  const data = (Array.isArray(raw) ? raw[0] : raw)?.page;

  return NextResponse.json({ ok: true, page: data }, { status: 201 });
}
