import { createSupabaseServerClient } from "@/lib/supabase/server";
import { NewsPanel } from "@/components/NewsPanel";
import { requireAdmin } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function NewsPage() {
  const admin = await requireAdmin("news.manage");
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.news, { p_limit: 500 });
  const news = Array.isArray(data) ? data : [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl text-moon">Новости и обновления</h1>
        <p className="mt-1 text-sm text-moon-dim">Опубликованные записи автоматически доступны Telegram-боту через единый источник данных Supabase.</p>
      </div>
      {error && <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Не удалось загрузить новости: {error.message}</div>}
      <NewsPanel initialNews={news} />
    </div>
  );
}
