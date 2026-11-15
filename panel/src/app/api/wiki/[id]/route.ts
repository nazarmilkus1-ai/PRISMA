import { NextResponse } from 'next/server';
import { safeApiError } from '@/lib/api-error';
import { z } from 'zod';
import { requireAdminContext } from '@/lib/require-admin';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { STAFF_RPC } from '@prisma-eco/contracts';

const UpdateSchema = z.object({
  title: z.string().trim().min(2).max(200).optional(),
  excerpt: z.string().trim().max(500).optional().nullable(),
  content: z.string().trim().min(1).optional(),
  category: z.string().trim().min(1).max(50).optional(),
  published: z.boolean().optional(),
  visibility: z.enum(['PUBLIC', 'MEMBER', 'STAFF']).optional(),
});

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = await requireAdminContext('wiki.view');
  if (!context) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('wiki_pages')
    .select('*')
    .eq('id', id)
    .single();

  if (error) return NextResponse.json({ error: safeApiError(error, 'Страница не найдена.') }, { status: 404 });

  return NextResponse.json({ page: data });
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = await requireAdminContext('wiki.manage');
  if (!context) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const { id } = await params;
  const parsed = UpdateSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data: raw, error } = await supabase.rpc(STAFF_RPC.manageWiki, {
    p_action: 'UPDATE',
    p_page_id: id,
    p_slug: null,
    p_title: parsed.data.title ?? null,
    p_excerpt: parsed.data.excerpt ?? null,
    p_content: parsed.data.content ?? null,
    p_category: parsed.data.category ?? null,
    p_published: parsed.data.published ?? null,
    p_visibility: parsed.data.visibility ?? null,
  });

  if (error) return NextResponse.json({ error: safeApiError(error, 'Не удалось обновить страницу Wiki.') }, { status: 409 });
  const data = (Array.isArray(raw) ? raw[0] : raw)?.page;

  return NextResponse.json({ ok: true, page: data });
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = await requireAdminContext('wiki.manage');
  if (!context) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc(STAFF_RPC.manageWiki, { p_action: 'DELETE', p_page_id: id });

  if (error) return NextResponse.json({ error: safeApiError(error, 'Не удалось удалить страницу Wiki.') }, { status: 409 });

  return NextResponse.json({ ok: true });
}