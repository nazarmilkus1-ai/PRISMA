"use client";

import { fetchJson, formatDateTime, formatNumber } from "@prisma-eco/shared";

import { useEffect, useState } from "react";
import { Card } from "@/components/ui";

type Kind = "applications" | "chat" | "audit";
type RowData = Record<string, unknown>;
type PageData = { rows: RowData[]; total: number; limit: number; offset: number };
const PAGE_SIZE = 50;

function useAnalyticsPage(period: string, kind: Kind, page: number) {
  const [data, setData] = useState<PageData>({ rows: [], total: 0, limit: PAGE_SIZE, offset: 0 });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const offset = (page - 1) * PAGE_SIZE;
    setLoading(true);
    setError(null);

    void (async () => {
      try {
        const query = new URLSearchParams({
          period,
          kind,
          limit: String(PAGE_SIZE),
          offset: String(offset),
        });
        const { response, data: payload } = await fetchJson<{ error?: string; rows?: RowData[]; total?: number; limit?: number; offset?: number }>("/admin/api/analytics/details?" + query.toString(), { cache: "no-store" });
        if (!response.ok) throw new Error(payload.error ?? "Не удалось загрузить записи.");
        if (active) {
          setData({
            rows: Array.isArray(payload.rows) ? payload.rows : [],
            total: Number(payload.total || 0),
            limit: Number(payload.limit || PAGE_SIZE),
            offset: Number(payload.offset || 0),
          });
        }
      } catch (e) {
        if (active) setError(e instanceof Error ? e.message : "Не удалось загрузить записи.");
      } finally {
        if (active) setLoading(false);
      }
    })();

    return () => { active = false; };
  }, [period, kind, page]);

  return { ...data, loading, error };
}

function text(value: unknown, fallback = "—") {
  return value === null || value === undefined || value === "" ? fallback : String(value);
}
function nameFor(row: RowData) {
  const mc = text(row.minecraft_nickname, "");
  const tg = text(row.telegram_username, "");
  const full = text(row.full_name, "");
  const userId = text(row.user_id, "");
  return mc || (tg ? "@" + tg : "") || full || userId || "—";
}

function Pager({ page, total, onChange }: { page: number; total: number; onChange: (next: number) => void }) {
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const from = total === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
  const to = Math.min(total, page * PAGE_SIZE);
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
      <p className="text-xs text-moon-dim">Записи {from}–{to} из {formatNumber(total)}</p>
      <div className="flex items-center gap-2">
        <button
          type="button"
          disabled={page <= 1}
          onClick={() => onChange(page - 1)}
          className="rounded-lg border border-border px-3 py-1.5 text-xs text-moon-dim hover:text-moon disabled:opacity-35"
        >
          Назад
        </button>
        <span className="min-w-16 text-center text-xs text-moon-dim">{page} / {totalPages}</span>
        <button
          type="button"
          disabled={page >= totalPages}
          onClick={() => onChange(page + 1)}
          className="rounded-lg border border-border px-3 py-1.5 text-xs text-moon-dim hover:text-moon disabled:opacity-35"
        >
          Далее
        </button>
      </div>
    </div>
  );
}

function TableState({ loading, error, empty }: { loading: boolean; error: string | null; empty: boolean }) {
  if (loading) return <p className="p-8 text-center text-sm text-moon-dim">Загружаю записи…</p>;
  if (error) return <p className="p-8 text-center text-sm text-danger">{error}</p>;
  if (empty) return <p className="p-8 text-center text-sm text-moon-dim">За выбранный период записей нет.</p>;
  return null;
}

export function AnalyticsDetailsTables({ period }: { period: "24h" | "7d" | "30d" | "all" }) {
  const [applicationPage, setApplicationPage] = useState(1);
  const [chatPage, setChatPage] = useState(1);
  const [auditPage, setAuditPage] = useState(1);
  const applications = useAnalyticsPage(period, "applications", applicationPage);
  const chats = useAnalyticsPage(period, "chat", chatPage);
  const audits = useAnalyticsPage(period, "audit", auditPage);

  return (
    <div className="space-y-4">
      <Card className="overflow-hidden">
        <div className="border-b border-border p-5">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="font-medium text-moon">Детально · заявки</h2>
            <span className="text-xs text-moon-dim">{formatNumber(applications.total)} записей за период</span>
          </div>
          <p className="mt-1 text-xs text-moon-dim">Полный список заявок без архива, включая Telegram username, причину отказа и ответы анкеты.</p>
        </div>
        <div className="max-h-[560px] overflow-auto">
          <table className="w-full min-w-[1250px] text-left text-sm">
            <thead className="sticky top-0 bg-panel">
              <tr className="border-b border-border text-[11px] uppercase tracking-wide text-moon-dim">
                <th className="p-3">Когда</th><th className="p-3">Заявка / игрок</th><th className="p-3">Telegram</th><th className="p-3">Статус</th><th className="p-3">Платформа / источник</th><th className="p-3">Цель</th><th className="p-3">О себе / причина отказа</th>
              </tr>
            </thead>
            <tbody>
              {applications.rows.map((row) => (
                <tr key={text(row.id)} className="border-b border-border/50 align-top">
                  <td className="whitespace-nowrap p-3 text-xs text-moon-dim">{formatDateTime(text(row.created_at))}</td>
                  <td className="p-3">
                    <p className="font-mono text-xs text-moon">#{text(row.application_no)} · {text(row.nickname)}</p>
                    <p className="mt-1 text-xs text-moon-dim">{text(row.full_name)} · возраст {text(row.age)}</p>
                  </td>
                  <td className="p-3 text-xs text-moon">
                    <p>{row.telegram_username ? "@" + text(row.telegram_username) : "username не указан"}</p>
                    <p className="mt-1 text-moon-dim">ID {text(row.telegram_id)}</p>
                  </td>
                  <td className="p-3 text-xs text-moon">{text(row.status)}</td>
                  <td className="p-3 text-xs text-moon-dim">{text(row.platform)}<p className="mt-1">{text(row.discovery_source)}</p></td>
                  <td className="max-w-[260px] whitespace-pre-wrap p-3 text-xs text-moon">{text(row.goal)}</td>
                  <td className="max-w-[320px] p-3 text-xs text-moon">
                    <p className="whitespace-pre-wrap">{text(row.about)}</p>
                    {row.rejection_reason ? <p className="mt-2 whitespace-pre-wrap text-danger">Причина: {text(row.rejection_reason)}</p> : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <TableState loading={applications.loading} error={applications.error} empty={applications.rows.length === 0} />
        </div>
        {!applications.loading && !applications.error && applications.total > PAGE_SIZE && (
          <Pager page={applicationPage} total={applications.total} onChange={setApplicationPage} />
        )}
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b border-border p-5">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="font-medium text-moon">Детально · Minecraft-чат</h2>
            <span className="text-xs text-moon-dim">{formatNumber(chats.total)} записей за период</span>
          </div>
          <p className="mt-1 text-xs text-moon-dim">Сообщения загружаются страницами по 50. Username показывается отдельно, даже если у игрока нет Minecraft-ника.</p>
        </div>
        <div className="max-h-[560px] overflow-auto">
          <table className="w-full min-w-[900px] text-left text-sm">
            <thead className="sticky top-0 bg-panel">
              <tr className="border-b border-border text-[11px] uppercase tracking-wide text-moon-dim">
                <th className="p-3">Когда</th><th className="p-3">Игрок / Telegram</th><th className="p-3">Мир</th><th className="p-3">Сообщение</th>
              </tr>
            </thead>
            <tbody>
              {chats.rows.map((row) => (
                <tr key={text(row.id)} className="border-b border-border/50 align-top">
                  <td className="whitespace-nowrap p-3 text-xs text-moon-dim">{formatDateTime(text(row.created_at))}</td>
                  <td className="p-3 text-xs text-moon">
                    <p>{nameFor(row)}</p>
                    <p className="mt-1 text-moon-dim">{row.telegram_username ? "@" + text(row.telegram_username) : "username не указан"}</p>
                  </td>
                  <td className="p-3 text-xs text-moon-dim">{text(row.world)}</td>
                  <td className="max-w-[600px] whitespace-pre-wrap p-3 text-sm text-moon">{text(row.message)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <TableState loading={chats.loading} error={chats.error} empty={chats.rows.length === 0} />
        </div>
        {!chats.loading && !chats.error && chats.total > PAGE_SIZE && (
          <Pager page={chatPage} total={chats.total} onChange={setChatPage} />
        )}
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b border-border p-5">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="font-medium text-moon">Детально · действия персонала</h2>
            <span className="text-xs text-moon-dim">{formatNumber(audits.total)} записей за период</span>
          </div>
          <p className="mt-1 text-xs text-moon-dim">Журнал действий: дата, сотрудник, действие и цель. Подробные данные изменений доступны в разделе «Аудит» по отдельным правам.</p>
        </div>
        <div className="max-h-[560px] overflow-auto">
          <table className="w-full min-w-[900px] text-left text-sm">
            <thead className="sticky top-0 bg-panel">
              <tr className="border-b border-border text-[11px] uppercase tracking-wide text-moon-dim">
                <th className="p-3">Когда</th><th className="p-3">Сотрудник</th><th className="p-3">Действие</th><th className="p-3">Цель</th>
              </tr>
            </thead>
            <tbody>
              {audits.rows.map((row) => (
                <tr key={text(row.id)} className="border-b border-border/50 align-top">
                  <td className="whitespace-nowrap p-3 text-xs text-moon-dim">{formatDateTime(text(row.created_at))}</td>
                  <td className="p-3 text-xs text-moon">
                    <p>{text(row.actor_name)}</p>
                    <p className="mt-1 text-moon-dim">ID {text(row.actor_tg_id)}</p>
                  </td>
                  <td className="p-3 font-mono text-xs text-moon">{text(row.action)}</td>
                  <td className="p-3 text-xs text-moon-dim">{row.target_type ? text(row.target_type) + " · " + text(row.target_id) : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <TableState loading={audits.loading} error={audits.error} empty={audits.rows.length === 0} />
        </div>
        {!audits.loading && !audits.error && audits.total > PAGE_SIZE && (
          <Pager page={auditPage} total={audits.total} onChange={setAuditPage} />
        )}
      </Card>
    </div>
  );
}
