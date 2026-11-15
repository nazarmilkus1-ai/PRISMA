import { requireAdmin } from '@/lib/require-admin';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { PageHeader } from '@prisma-eco/ui';
import { WikiPanel } from '@/components/WikiPanel';

export default async function WikiDashboardPage() {
  const admin = await requireAdmin('wiki.view');
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data: pages, error } = await supabase
    .from('wiki_pages')
    .select('*')
    .order('updated_at', { ascending: false });

  if (error) {
    console.error('Wiki pages fetch error:', error);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Контент"
        title="Wiki"
        description="Управление страницами Wiki: создание, редактирование, публикация и настройка видимости."
      />
      <WikiPanel initialPages={(pages ?? []) as any} />
    </div>
  );
}
