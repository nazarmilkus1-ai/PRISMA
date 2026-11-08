"use client";

import { formatDateTime } from "@prisma-eco/shared";

import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { Avatar, Badge, Card, SearchBar, StatusBadge, Tabs } from "@/components/ui";
import { SimplePagination } from "@prisma-eco/ui";
import { ConfirmModal, Modal } from "@/components/Modal";

type Application = {
  id: string; application_no: number; full_name: string; age: number; nickname: string; platform: "JAVA" | "BEDROCK";
  discovery_source: string; status: "PENDING" | "ACCEPTED" | "REJECTED"; rejection_reason: string | null;
  created_at: string; user_id: string; birth_date: string | null; goal: string | null; about: string | null;
  reviewed_at: string | null; reviewed_by_name: string | null; staff_notes: string | null;
  users: { id: string; telegram_id: number; telegram_username: string | null; first_name: string | null; last_name: string | null; minecraft_nickname: string | null; platform: "JAVA" | "BEDROCK" | null; status: string | null; is_whitelisted: boolean; last_seen_at: string | null; } | { id: string; telegram_id: number; telegram_username: string | null; first_name: string | null; last_name: string | null; minecraft_nickname: string | null; platform: "JAVA" | "BEDROCK" | null; status: string | null; is_whitelisted: boolean; last_seen_at: string | null; }[] | null;
};

type Detail = Application & {
  history: { id: number; action: string; actor_tg_id: number | null; reason: string | null; created_at: string }[];
};

const FILTERS = [
  { key: "ALL", label: "Все" }, { key: "PENDING", label: "Ожидают" },
  { key: "ACCEPTED", label: "Принятые" }, { key: "REJECTED", label: "Архив" },
] as const;
const PAGE_SIZE = 10;

function userOf(app: Application) { return Array.isArray(app.users) ? app.users[0] : app.users; }
function telegramOf(app: Application) { const u = userOf(app); return u?.telegram_username ? `@${u.telegram_username}` : u?.telegram_id ?? "—"; }

function isOnline(u: Application["users"]) { const x = userOf({ users: u } as Application); return !!x?.last_seen_at && Date.now() - new Date(x.last_seen_at).getTime() <= 15 * 60_000; }

export function ApplicationsPanel({ initialApplications }: { initialApplications: Application[] }) {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["key"]>("ALL");
  const [search, setSearch] = useState(""); const [platform, setPlatform] = useState<"ALL"|"JAVA"|"BEDROCK">("ALL");
  const [source, setSource] = useState("ALL"); const [from, setFrom] = useState(""); const [to, setTo] = useState("");
  const [page, setPage] = useState(1); const [selected, setSelected] = useState<Detail | null>(null);
  const [approveTarget, setApproveTarget] = useState<Application | null>(null); const [rejectTarget, setRejectTarget] = useState<Application | null>(null);
  const [reason, setReason] = useState(""); const [busy, setBusy] = useState(false); const [isPending, startTransition] = useTransition();
  const router = useRouter();

  useEffect(() => {
    const supabase = createSupabaseBrowserClient();
    const channel = supabase.channel("applications-changes").on("postgres_changes", { event: "*", schema: "public", table: "applications" }, () => startTransition(() => router.refresh())).subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [router]);

  async function openDetail(id: string) {
    const res = await fetch(`/admin/api/applications/${id}`, { cache: "no-store" });
    if (res.ok) setSelected(await res.json());
  }

  async function act(id: string, action: "approve"|"reject", rejectionReason?: string) {
    setBusy(true);
    const res = await fetch(`/admin/api/applications/${id}`, { method:"PATCH", headers:{"Content-Type":"application/json"}, body:JSON.stringify({action, reason:rejectionReason}) });
    if (!res.ok) { setBusy(false); return; }
    setBusy(false); setApproveTarget(null); setRejectTarget(null); setReason(""); setSelected(null); router.refresh();
  }

  const sources = useMemo(() => Array.from(new Set(initialApplications.map(a => a.discovery_source).filter(Boolean))).sort(), [initialApplications]);
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return initialApplications.filter(a => {
      if (filter !== "ALL" && a.status !== filter) return false;
      if (platform !== "ALL" && a.platform !== platform) return false;
      if (source !== "ALL" && a.discovery_source !== source) return false;
      const created = a.created_at.slice(0,10);
      if (from && created < from) return false; if (to && created > to) return false;
      if (!q) return true;
      const u = userOf(a);
      return [a.application_no, a.full_name, a.nickname, a.goal, a.about, a.discovery_source, u?.telegram_username, u?.telegram_id].filter(Boolean).some(v => String(v).toLowerCase().includes(q));
    });
  }, [initialApplications, filter, platform, source, from, to, search]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visible = filtered.slice((currentPage-1)*PAGE_SIZE, currentPage*PAGE_SIZE);

  function resetFilters() { setSearch(""); setPlatform("ALL"); setSource("ALL"); setFrom(""); setTo(""); setPage(1); }

  return (
    <div className="space-y-4">
      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-center gap-2 border-b border-border p-3">
          <div className="flex min-w-0 items-center gap-2"><Tabs tabs={FILTERS as unknown as {key: typeof filter; label: string}[]} active={filter} onChange={(v)=>{setFilter(v as typeof filter);setPage(1)}} />{isPending ? <span className="shrink-0 text-xs text-moon-dim">обновление…</span> : null}</div>
        </div>
        <div className="grid grid-cols-1 gap-2 border-b border-border p-3 md:grid-cols-2 xl:grid-cols-6">
          <SearchBar value={search} onChange={v=>{setSearch(v);setPage(1)}} placeholder="Имя, @username, Telegram ID, Minecraft…" className="xl:col-span-2" />
          <select value={platform} onChange={e=>{setPlatform(e.target.value as typeof platform);setPage(1)}} className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon"><option value="ALL">Все платформы</option><option value="JAVA">Java</option><option value="BEDROCK">Bedrock</option></select>
          <select value={source} onChange={e=>{setSource(e.target.value);setPage(1)}} className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon"><option value="ALL">Все источники</option>{sources.map(s=><option key={s} value={s}>{s}</option>)}</select>
          <input type="date" value={from} onChange={e=>{setFrom(e.target.value);setPage(1)}} className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon" />
          <input type="date" value={to} onChange={e=>{setTo(e.target.value);setPage(1)}} className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon" />
        </div>
        {(search || platform !== "ALL" || source !== "ALL" || from || to) && <div className="flex items-center justify-between border-b border-border px-3 py-2 text-xs text-moon-dim"><span>{filtered.length} заявок соответствуют выбранным фильтрам</span><button onClick={resetFilters} className="text-ember hover:underline">Сбросить</button></div>}
        <div className="divide-y divide-border">
          {visible.map(app => {
            const u = userOf(app);
            return <div key={app.id} className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center">
              <button className="flex min-w-0 flex-1 items-center gap-3 text-left" onClick={()=>void openDetail(app.id)}>
                <Avatar name={app.full_name} size="md" />
                <div className="min-w-0"><p className="truncate text-sm text-moon">{app.full_name}</p><p className={"mt-0.5 text-xs "+(isOnline(u)?"text-success":"text-moon-dim")}><span className={"mr-1.5 inline-block h-1.5 w-1.5 rounded-full align-middle "+(isOnline(u)?"bg-success":"bg-moon-dim/30")} />{isOnline(u)?"онлайн":"офлайн"}</p><p className="truncate font-mono text-xs text-moon-dim">{app.nickname} · {telegramOf(app)}</p><p className="truncate text-xs text-moon-dim">{app.platform === "JAVA" ? "Java" : "Bedrock"} · {app.discovery_source} · {formatDateTime(app.created_at)}</p></div>
              </button>
              <div className="flex items-center gap-2"><StatusBadge status={app.status} />
                {app.status === "PENDING" && <button onClick={()=>setApproveTarget(app)} className="rounded-lg bg-success/15 px-2.5 py-1.5 text-success">✓</button>}
                {app.status !== "REJECTED" && <button onClick={()=>setRejectTarget(app)} className="rounded-lg bg-danger/15 px-2.5 py-1.5 text-danger">✕</button>}
                <button onClick={()=>void openDetail(app.id)} className="rounded-lg border border-border px-3 py-1.5 text-xs text-moon-dim hover:text-moon">Открыть</button>
              </div>
            </div>;
          })}
          {visible.length === 0 && <div className="p-10 text-center text-sm text-moon-dim">Ничего не найдено.</div>}
        </div>
        {totalPages > 1 && <div className="border-t border-border p-3"><SimplePagination page={currentPage} totalPages={totalPages} onChange={setPage} /></div>}
      </Card>

      <Modal open={!!selected} onClose={()=>setSelected(null)}>
        {selected && <ApplicationDetail application={selected} onClose={()=>setSelected(null)} onApprove={()=>setApproveTarget(selected)} onReject={()=>setRejectTarget(selected)} />}
      </Modal>
      <ConfirmModal open={!!approveTarget} onClose={()=>setApproveTarget(null)} onConfirm={()=>approveTarget && void act(approveTarget.id,"approve")} title="Принять анкету?" description={approveTarget ? `${approveTarget.full_name} · ${approveTarget.nickname}` : ""} confirmLabel="Принять" tone="success" busy={busy}/>
      <ConfirmModal open={!!rejectTarget} onClose={()=>{setRejectTarget(null);setReason("")}} onConfirm={()=>rejectTarget && void act(rejectTarget.id,"reject",reason || undefined)} title={rejectTarget?.status === "ACCEPTED" ? "Снять с whitelist?" : "Отклонить анкету?"} description={rejectTarget ? `${rejectTarget.full_name} · ${rejectTarget.nickname}` : ""} confirmLabel={rejectTarget?.status === "ACCEPTED" ? "Снять" : "Отклонить"} tone="danger" busy={busy}>
        <input autoFocus value={reason} onChange={e=>setReason(e.target.value)} placeholder="Причина (необязательно)" className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon" />
      </ConfirmModal>
    </div>
  );
}

function ApplicationDetail({ application, onClose, onApprove, onReject }: { application: Detail; onClose:()=>void; onApprove:()=>void; onReject:()=>void }) {
  const u = userOf(application);
  return <div className="space-y-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><p className="font-mono text-xs uppercase tracking-wider text-curse">Анкета №{application.application_no}</p><h2 className="mt-1 font-display text-2xl text-moon">{application.full_name}</h2><p className="text-sm text-moon-dim">{application.nickname} · {application.platform === "JAVA" ? "Java" : "Bedrock"}</p></div>
      <StatusBadge status={application.status} />
    </div>
    <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <Field label="Telegram" value={String(telegramOf(application))} /><Field label="Telegram ID" value={String(u?.telegram_id ?? "—")} />
      <Field label="Дата рождения" value={application.birth_date ?? "—"} />
      <Field label="Minecraft" value={u?.minecraft_nickname ?? application.nickname} /><Field label="Платформа" value={application.platform === "JAVA" ? "Java" : "Bedrock"} />
      <Field label="Источник" value={application.discovery_source} /><Field label="Подано" value={formatDateTime(application.created_at)} />
      <Field label="Рассмотрено" value={application.reviewed_at ? formatDateTime(application.reviewed_at) : "—"} /><Field label="Кто рассмотрел" value={application.reviewed_by_name ?? "—"} />
    </div>
    <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
      <TextField label="Цель" value={application.goal} /><TextField label="О себе" value={application.about} />
    </div>
    {application.rejection_reason && <div className="rounded-lg border border-danger/30 bg-danger/10 p-3"><p className="text-xs text-danger">Причина отказа</p><p className="mt-1 text-sm text-moon">{application.rejection_reason}</p></div>}
    <div className="border-t border-border pt-4"><h3 className="text-sm font-medium text-moon">История</h3><div className="mt-2 space-y-2">{application.history?.length ? application.history.map(h=><div key={h.id} className="rounded-lg border border-border bg-panel-raised/40 p-3"><p className="text-sm text-moon">{h.action}</p><p className="mt-1 text-xs text-moon-dim">{formatDateTime(h.created_at)} · {h.actor_tg_id ?? "система"}{h.reason ? ` · ${h.reason}`:""}</p></div>) : <p className="text-sm text-moon-dim">История пока пуста.</p>}</div></div>
    <div className="flex flex-wrap justify-end gap-2 pt-1">
      <button onClick={onClose} className="rounded-lg border border-border px-4 py-2 text-sm text-moon-dim">Закрыть</button>
      <button onClick={onReject} className="rounded-lg bg-danger/15 px-4 py-2 text-sm text-danger">{application.status === "ACCEPTED" ? "Снять whitelist" : "Отклонить"}</button>
      {application.status === "PENDING" && <button onClick={onApprove} className="rounded-lg bg-success/15 px-4 py-2 text-sm text-success">Принять</button>}
    </div>
  </div>;
}
function Field({label,value}:{label:string;value:string}) { return <div className="rounded-lg border border-border bg-panel-raised/40 p-3"><p className="text-xs text-moon-dim">{label}</p><p className="mt-1 break-words text-sm text-moon">{value}</p></div>; }
function TextField({label,value}:{label:string;value:string|null}) { return <div className="rounded-lg border border-border bg-panel-raised/40 p-3 min-h-24"><p className="text-xs text-moon-dim">{label}</p><p className="mt-1 whitespace-pre-wrap break-words text-sm text-moon">{value || "—"}</p></div>; }
