import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { MarketPanel } from "@/components/MarketPanel";

import { STAFF_RPC } from "@prisma-eco/contracts";

type ListingRow = {
  id: string;
  seller_id: string;
  kind: string;
  title: string;
  description: string | null;
  price_text: string | null;
  terms: string | null;
  status: string;
  effective_status: string;
  created_at: string;
  updated_at: string;
  expires_at: string | null;
  minecraft_nickname: string | null;
  telegram_username: string | null;
  open_inquiries: number;
  total_inquiries: number;
};

export default async function MarketPage() {
  const context = await requireAdminContext("market.view");
  if (!context) return null;

  const db = await createSupabaseServerClient();
  const { data, error } = await db.rpc(STAFF_RPC.market, {
    p_query: "",
    p_status: null,
    p_limit: 300,
  });

  return (
    <div className="space-y-6">
      <div>
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-curse">Сообщество</p>
        <h1 className="mt-1 font-display text-2xl text-moon">Рынок</h1>
        <p className="mt-1 text-sm text-moon-dim">
          Объявления участников, запросы и модерация рынка без внутренней валюты.
        </p>
      </div>
      {error ? (
        <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">
          Не удалось загрузить рынок: {error.message}
        </div>
      ) : (
        <MarketPanel initialListings={(Array.isArray(data) ? data : []) as ListingRow[]} />
      )}
    </div>
  );
}
