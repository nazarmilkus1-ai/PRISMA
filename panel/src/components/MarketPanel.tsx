"use client";

import { MARKET_LISTING_KIND_LABELS, MARKET_LISTING_STATUS_LABELS } from "@prisma-eco/contracts";

import { useMemo, useState } from "react";
import { fetchJson, formatDateTime } from "@prisma-eco/shared";
import { Badge, Card, SearchBar, InfoItem } from "@/components/ui";

type Listing = {
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

type Inquiry = {
  id: string;
  listing_id: string;
  requester_nickname: string | null;
  seller_nickname: string | null;
  message: string;
  response: string | null;
  status: string;
  created_at: string;
  responded_at: string | null;
  closed_at: string | null;
};

function statusTone(status: string): "success" | "warn" | "danger" | "neutral" {
  if (status === "ACTIVE") return "success";
  if (status === "EXPIRED") return "warn";
  if (status === "CLOSED") return "danger";
  return "neutral";
}

function fmt(value: string | null) { return value ? formatDateTime(value) : "—"; }

export function MarketPanel({ initialListings }: { initialListings: Listing[] }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("ALL");
  const [selected, setSelected] = useState<Listing | null>(null);
  const [inquiries, setInquiries] = useState<Inquiry[]>([]);
  const [loadingInquiries, setLoadingInquiries] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return initialListings.filter((item) => {
      if (status !== "ALL" && item.effective_status !== status) return false;
      if (!q) return true;
      return [item.title, item.description, item.price_text, item.minecraft_nickname]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q));
    });
  }, [initialListings, query, status]);

  async function openInquiries(item: Listing) {
    setSelected(item);
    setLoadingInquiries(true);
    setError(null);
    const { response, data } = await fetchJson<{ error?: string; inquiries?: Inquiry[] }>(`/admin/api/market?listing_id=${encodeURIComponent(item.id)}`, { cache: "no-store" });
    setLoadingInquiries(false);
    if (!response.ok) {
      setError(data.error ?? "Не удалось загрузить запросы.");
      return;
    }
    setInquiries(data.inquiries ?? []);
  }

  async function manage(action: "CLOSE_LISTING" | "CLOSE_INQUIRY", id: string) {
    setBusy(id);
    setError(null);
    const response = await fetch("/admin/api/market", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(action === "CLOSE_LISTING" ? { action, listing_id: id } : { action, inquiry_id: id }),
    });
    const data = await response.json().catch(() => ({}));
    setBusy(null);

    if (!response.ok) {
      setError(data.error ?? "Не удалось выполнить действие.");
      return;
    }

    window.location.reload();
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_30rem]">
      <Card className="overflow-hidden">
        <div className="space-y-3 border-b border-border p-4">
          <SearchBar value={query} onChange={setQuery} placeholder="Заголовок, продавец или цена…" />
          <div className="flex flex-wrap items-center gap-1">
            {[
              ["ALL", "Все"],
              ["ACTIVE", "Активные"],
              ["EXPIRED", "Истёкшие"],
              ["CLOSED", "Закрытые"],
            ].map(([key, label]) => (
              <button
                key={key}
                onClick={() => setStatus(key)}
                className={`rounded-lg px-3 py-1.5 text-xs ${status === key ? "bg-panel-raised text-moon" : "text-moon-dim hover:text-moon"}`}
              >
                {label}
              </button>
            ))}
            <span className="ml-auto text-xs text-moon-dim">{visible.length} объявлений</span>
          </div>
        </div>

        <div className="divide-y divide-border">
          {visible.map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => void openInquiries(item)}
              className={`block w-full p-4 text-left transition-colors hover:bg-panel-raised/40 ${selected?.id === item.id ? "bg-panel-raised/60" : ""}`}
            >
              <div className="flex items-start gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge tone={statusTone(item.effective_status)}>{MARKET_LISTING_STATUS_LABELS[item.effective_status] ?? item.effective_status}</Badge>
                    <span className="text-xs text-moon-dim">{MARKET_LISTING_KIND_LABELS[item.kind] ?? item.kind}</span>
                  </div>
                  <h2 className="mt-1 truncate text-sm font-medium text-moon">{item.title}</h2>
                  <p className="mt-1 truncate text-xs text-moon-dim">
                    {item.minecraft_nickname ?? "Без Minecraft-ника"} · {item.price_text ?? "Цена не указана"}
                  </p>
                </div>
                <div className="shrink-0 text-right text-xs text-moon-dim">
                  <p>{item.open_inquiries} открытых</p>
                  <p>{item.total_inquiries} всего</p>
                </div>
              </div>
            </button>
          ))}
          {!visible.length && <div className="p-10 text-center text-sm text-moon-dim">Объявления не найдены.</div>}
        </div>
      </Card>

      <Card className="p-5 xl:sticky xl:top-4 xl:h-fit">
        {!selected ? (
          <div className="py-10 text-center text-sm text-moon-dim">Выберите объявление, чтобы открыть детали и запросы.</div>
        ) : (
          <div className="space-y-4">
            <div>
              <div className="flex flex-wrap gap-2">
                <Badge tone={statusTone(selected.effective_status)}>{MARKET_LISTING_STATUS_LABELS[selected.effective_status] ?? selected.effective_status}</Badge>
                <Badge>{MARKET_LISTING_KIND_LABELS[selected.kind] ?? selected.kind}</Badge>
              </div>
              <h2 className="mt-2 text-lg font-medium text-moon">{selected.title}</h2>
              <p className="mt-1 text-xs text-moon-dim">{selected.minecraft_nickname ?? "Без Minecraft-ника"}</p>
            </div>

            {selected.description && <p className="whitespace-pre-wrap rounded-lg bg-panel-raised p-3 text-sm leading-6 text-moon">{selected.description}</p>}
            <div className="grid grid-cols-2 gap-2">
              <InfoItem label="Цена" value={selected.price_text ?? "—"} />
              <InfoItem label="Условия" value={selected.terms ?? "—"} />
              <InfoItem label="Создано" value={fmt(selected.created_at)} />
              <InfoItem label="Срок" value={fmt(selected.expires_at)} />
            </div>

            {selected.status === "ACTIVE" ? (
              <button
                type="button"
                disabled={busy === selected.id}
                onClick={() => void manage("CLOSE_LISTING", selected.id)}
                className="w-full rounded-lg border border-danger/40 px-3 py-2.5 text-sm text-danger hover:bg-danger/10 disabled:opacity-40"
              >
                {busy === selected.id ? "Закрываем…" : "Снять объявление"}
              </button>
            ) : null}

            <div className="border-t border-border pt-4">
              <div className="flex items-center justify-between gap-2">
                <h3 className="text-sm font-medium text-moon">Запросы</h3>
                <span className="text-xs text-moon-dim">{inquiries.length}</span>
              </div>

              {loadingInquiries ? (
                <p className="py-6 text-center text-sm text-moon-dim">Загрузка…</p>
              ) : inquiries.length ? (
                <div className="mt-3 max-h-[55vh] space-y-3 overflow-y-auto pr-1">
                  {inquiries.map((item) => (
                    <div key={item.id} className="rounded-lg border border-border p-3">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="text-sm text-moon">{item.requester_nickname ?? "Участник"} → {item.seller_nickname ?? "Участник"}</p>
                          <p className="text-xs text-moon-dim">{item.status} · {fmt(item.created_at)}</p>
                        </div>
                        {item.status !== "CLOSED" ? (
                          <button
                            type="button"
                            disabled={busy === item.id}
                            onClick={() => void manage("CLOSE_INQUIRY", item.id)}
                            className="shrink-0 rounded-md border border-danger/40 px-2 py-1 text-xs text-danger hover:bg-danger/10 disabled:opacity-40"
                          >
                            Закрыть
                          </button>
                        ) : null}
                      </div>
                      <p className="mt-2 whitespace-pre-wrap rounded-md bg-panel-raised p-2.5 text-sm text-moon">{item.message}</p>
                      {item.response ? <p className="mt-2 whitespace-pre-wrap rounded-md border border-border p-2.5 text-sm text-moon">Ответ: {item.response}</p> : null}
                    </div>
                  ))}
                </div>
              ) : (
                <p className="py-6 text-center text-sm text-moon-dim">Запросов нет.</p>
              )}
            </div>
          </div>
        )}
        {error ? <p className="mt-4 rounded-lg border border-danger/30 bg-danger/10 px-3 py-2 text-xs text-danger">{error}</p> : null}
      </Card>
    </div>
  );
}

