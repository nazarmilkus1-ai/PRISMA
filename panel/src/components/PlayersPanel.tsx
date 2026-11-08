"use client";

import Link from "next/link";
import { fetchJson, formatDateTime } from "@prisma-eco/shared";
import { useMemo, useState } from "react";
import { Avatar, Badge, Card, SearchBar, Skeleton } from "@/components/ui";
import { SimplePagination } from "@prisma-eco/ui";

type Player = {
  id: string; telegram_id: number; telegram_username: string | null; first_name: string | null; full_name: string | null;
  minecraft_nickname: string | null; platform: "JAVA" | "BEDROCK" | null; status: "PENDING" | "ACCEPTED" | "REJECTED";
  is_whitelisted: boolean; is_banned: boolean; is_muted: boolean; muted_until: string | null;
  rating: number; activity_score: number; last_seen_at: string | null; clan_id: string | null; created_at: string;
  application_count?: number;
  latest_application?: {
    id: string;
    application_no: number | null;
    status: string;
    full_name: string | null;
    age: number | null;
    nickname: string | null;
    platform: string | null;
    discovery_source: string | null;
    birth_date: string | null;
    goal: string | null;
    about: string | null;
    created_at: string;
    updated_at: string | null;
    reviewed_at: string | null;
    reviewed_by_name: string | null;
    rejection_reason: string | null;
    staff_notes: string | null;
  } | null;
};
type Application = {
  id: string;
  application_no?: number | null;
  status: string;
  full_name?: string | null;
  age?: number | null;
  nickname: string | null;
  platform: string | null;
  discovery_source: string | null;
  birth_date: string | null;
  goal: string | null;
  about: string | null;
  created_at: string;
  updated_at?: string | null;
  reviewed_at: string | null;
  reviewed_by_tg_id?: number | null;
  reviewed_by_name: string | null;
  rejection_reason: string | null;
  cooldown_until?: string | null;
  staff_notes?: string | null;
  is_archived?: boolean | null;
};

type ModerationEntry = {
  id: string | number;
  type: string;
  reason?: string | null;
  created_at: string;
};

type ReportEntry = {
  id: string | number;
  ticket_no?: number | null;
  type: string;
  status: string;
  created_at: string;
};

type ClanSummary = {
  clans?: { name?: string | null } | null;
  role?: string | null;
} | null;

type Detail = {
  player: Player & { last_name?: string | null; birth_date?: string | null; age?: number | null; level?: number; xp?: number; mojang_uuid?: string | null; clan_name?: string | null; clan_tag?: string | null; punishment_count?: number; reports_created?: number; applications_count?: number; };
  applications: Application[]; moderation: ModerationEntry[]; reports: ReportEntry[]; votes: unknown[]; clan: ClanSummary; achievements: unknown[]; quests: unknown[];
  minecraft_auth?: { configured?: boolean; locked_until?: string | null; last_login_at?: string | null } | null;
};
const PAGE_SIZE = 20;
type Filter = "ALL" | "WHITELIST" | "BANNED" | "MUTED";

function statusTone(p: Player) { if (p.is_banned) return "danger" as const; if (p.is_muted) return "warn" as const; if (p.is_whitelisted) return "success" as const; return "neutral" as const; }
function statusLabel(p: Player) {
  if (p.is_banned) return "Бан";
  if (p.is_muted) return "Мут";
  if (p.is_whitelisted) return "Whitelist";
  if (p.status === "PENDING" && !p.minecraft_nickname) return "Без анкеты";
  if (p.status === "PENDING") return "Ожидает";
  return "Неактивен";
}
function applicationStatusLabel(status: string) {
  if (status === "ACCEPTED") return "принята";
  if (status === "REJECTED") return "отклонена";
  if (status === "PENDING") return "на рассмотрении";
  return status || "статус не указан";
}
function online(p: Player) { return !!p.last_seen_at && Date.now() - new Date(p.last_seen_at).getTime() <= 15 * 60_000; }
function fmt(v: string | null | undefined) { return v ? formatDateTime(v) : "—"; }

export function PlayersPanel({ initialPlayers }: { initialPlayers: Player[] }) {
  const [search, setSearch] = useState(""); const [filter, setFilter] = useState<Filter>("ALL"); const [page, setPage] = useState(1);
  const [detail, setDetail] = useState<Detail | null>(null); const [loading, setLoading] = useState(false); const [detailError, setDetailError] = useState(""); const [tab, setTab] = useState("profile");

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return initialPlayers.filter(p => {
      if (filter === "WHITELIST" && !p.is_whitelisted) return false;
      if (filter === "BANNED" && !p.is_banned) return false;
      if (filter === "MUTED" && !p.is_muted) return false;
      if (!q) return true;
      const application = p.latest_application;
      return [
        p.minecraft_nickname, p.telegram_username, p.full_name, p.first_name, p.telegram_id,
        application?.application_no, application?.status, application?.full_name,
        application?.nickname, application?.discovery_source, application?.goal, application?.about,
      ].filter(Boolean).some(v => String(v).toLowerCase().includes(q));
    });
  }, [initialPlayers, search, filter]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE)); const currentPage = Math.min(page, totalPages);
  const visible = filtered.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);

  async function openPlayer(p: Player) {
    setLoading(true);
    setDetailError("");
    setDetail(null);
    setTab("profile");
    try {
      const { response: res, data } = await fetchJson<Detail & { error?: string }>(`/api/players/${p.id}`, { cache: "no-store" });
      if (!res.ok) {
        setDetailError(typeof data?.error === "string" ? data.error : "Не удалось загрузить профиль игрока.");
        return;
      }
      setDetail(data);
    } catch {
      setDetailError("Не удалось загрузить профиль игрока.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_28rem]">
      <Card className="overflow-hidden">
        <div className="space-y-3 border-b border-border p-4">
          <SearchBar value={search} onChange={v => { setSearch(v); setPage(1); }} placeholder="Minecraft-ник, @username, Telegram ID или имя…" />
          <div className="flex flex-wrap gap-1">
            {(["ALL","WHITELIST","BANNED","MUTED"] as Filter[]).map(k => <button key={k} onClick={()=>{setFilter(k);setPage(1)}} className={`rounded-lg px-3 py-1.5 text-xs ${filter===k ? "bg-panel-raised text-moon" : "text-moon-dim hover:text-moon"}`}>{k==="ALL"?"Все":k==="WHITELIST"?"Whitelist":k==="BANNED"?"Бани":"Мути"}</button>)}
            <span className="ml-auto self-center text-xs text-moon-dim">{filtered.length} игроков</span>
          </div>
        </div>
        <div className="divide-y divide-border">
          {visible.map((p, index) => <button key={p.id} onClick={()=>void openPlayer(p)} style={{ animationDelay: `${Math.min(index, 7) * 35}ms` }} className={`prisma-list-enter flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-panel-raised/50 ${detail?.player.id===p.id?"bg-panel-raised/70":""}`}>
            <Avatar name={p.minecraft_nickname ?? p.telegram_username ?? p.full_name ?? "?"} size="md"/>
            <span className="min-w-0 flex-1"><span className="flex items-center gap-2"><span className="truncate font-mono text-sm text-moon">{p.minecraft_nickname ?? "Без Minecraft-ника"}</span>{online(p)&&<span className="h-1.5 w-1.5 rounded-full bg-success"/>}</span><span className="block truncate text-xs text-moon-dim">Telegram: {p.telegram_username ? `@${p.telegram_username}` : "username не указан"} · ID {p.telegram_id}</span><span className="block truncate text-[11px] text-moon-dim">{p.full_name ?? "Имя не указано"} · {p.platform === "JAVA" ? "Java" : p.platform === "BEDROCK" ? "Bedrock" : "платформа не указана"}</span>{p.latest_application ? <><span className="mt-1 block truncate text-[11px] text-moon-dim">Анкет: {p.application_count ?? 1} · №{p.latest_application.application_no ?? "—"} · {applicationStatusLabel(p.latest_application.status)} · {p.latest_application.age != null ? p.latest_application.age + " лет" : "возраст не указан"} · {p.latest_application.discovery_source ?? "источник не указан"}</span><span className="block truncate text-[11px] text-moon-dim">{p.latest_application.goal || p.latest_application.about || "Текст анкеты отсутствует"}</span></> : <span className="mt-1 block truncate text-[11px] text-moon-dim">Анкеты нет</span>}</span>
            <Badge tone={statusTone(p)}>{statusLabel(p)}</Badge>
          </button>)}
          {!visible.length && <div className="p-10 text-center text-sm text-moon-dim">Игроки не найдены.</div>}
        </div>
        {totalPages>1&&<div className="border-t border-border p-3"><SimplePagination page={currentPage} totalPages={totalPages} onChange={setPage}/></div>}
      </Card>

      <Card className="p-5 xl:sticky xl:top-4 xl:h-fit">
        {loading ? <div className="space-y-4 py-2">
            <div className="flex items-start gap-3"><Skeleton className="h-12 w-12 shrink-0 rounded-full"/><div className="min-w-0 flex-1 space-y-2"><Skeleton className="h-5 w-40"/><Skeleton className="h-3 w-56"/><Skeleton className="h-3 w-44"/></div></div>
            <div className="grid grid-cols-2 gap-2">{[0,1,2,3].map(i=><Skeleton key={i} className="h-16 rounded-lg"/>)}</div>
            <div className="space-y-2">{[0,1,2,3,4].map(i=><Skeleton key={i} className="h-9 rounded-lg"/>)}</div>
          </div> : detailError ? <div className="rounded-lg border border-danger/30 bg-danger/10 p-4 text-sm text-danger">{detailError}</div> : !detail ? <div className="py-10 text-center text-sm text-moon-dim">Выберите игрока, чтобы открыть его профиль.</div> :
          <div className="space-y-4">
            <div className="flex items-start gap-3"><Avatar name={detail.player.minecraft_nickname ?? detail.player.full_name ?? "?"} size="lg"/><div className="min-w-0"><h2 className="truncate font-mono text-lg text-moon">{detail.player.minecraft_nickname ?? "Без Minecraft-ника"}</h2><p className="truncate text-sm text-moon">{detail.player.full_name ?? "Имя не указано"}</p><p className="truncate text-xs text-moon-dim">Telegram: {detail.player.telegram_username ? `@${detail.player.telegram_username}` : "username не указан"} · ID {detail.player.telegram_id}</p></div></div>
            <div className="flex flex-wrap gap-2"><Badge tone={statusTone(detail.player)}>{statusLabel(detail.player)}</Badge>{detail.player.platform&&<Badge>{detail.player.platform==="JAVA"?"Java":"Bedrock"}</Badge>}{detail.player.platform==="JAVA" && detail.minecraft_auth && <Badge tone={detail.minecraft_auth.locked_until && new Date(detail.minecraft_auth.locked_until).getTime() > Date.now() ? "warn" : detail.minecraft_auth.configured ? "success" : "neutral"}>{detail.minecraft_auth.locked_until && new Date(detail.minecraft_auth.locked_until).getTime() > Date.now() ? "Auth заблокирована" : detail.minecraft_auth.configured ? "Auth настроена" : "Auth не настроена"}</Badge>}{detail.player.platform==="BEDROCK" && <Badge tone="neutral">Auth не требуется</Badge>}{detail.player.clan_name&&<Badge tone="curse">{detail.player.clan_tag ? `[${detail.player.clan_tag}] `: ""}{detail.player.clan_name}</Badge>}</div>
            <div className="grid grid-cols-2 gap-2"><Box label="Рейтинг" value={String(detail.player.rating ?? 0)}/><Box label="Активность" value={String(detail.player.activity_score ?? 0)}/><Box label="Уровень" value={String(detail.player.level ?? 0)}/><Box label="XP" value={String(detail.player.xp ?? 0)}/></div>
            <div className="flex flex-wrap gap-1 border-b border-border pb-2">{[["profile","Профиль"],["applications","Анкеты"],["moderation","Наказания"],["reports","Репорти"],["community","Сообщество"]].map(([k,l])=><button key={k} onClick={()=>setTab(k)} className={`rounded-lg px-2.5 py-1.5 text-xs ${tab===k?"bg-panel-raised text-moon":"text-moon-dim hover:text-moon"}`}>{l}</button>)}</div>
            {tab==="profile"&&<div className="space-y-2 text-sm">
              <Row k="Telegram username" v={detail.player.telegram_username ? `@${detail.player.telegram_username}` : "не указан"}/><Row k="Telegram ID" v={String(detail.player.telegram_id)}/><Row k="Имя" v={detail.player.full_name ?? "—"}/><Row k="Дата рождения" v={detail.player.birth_date ?? "—"}/><Row k="Возраст" v={detail.player.age != null ? String(detail.player.age) : "—"}/><Row k="Дата регистрации" v={fmt(detail.player.created_at)}/><Row k="Последний онлайн" v={fmt(detail.player.last_seen_at)}/><Row k="PRISMA Auth" v={detail.player.platform==="JAVA" ? (detail.minecraft_auth?.configured ? "Настроена" : "Не настроена") : "Не требуется"}/><Row k="Minecraft UUID" v={detail.player.mojang_uuid ?? "—"}/><Row k="Наказаний" v={String(detail.player.punishment_count ?? detail.moderation.length)}/><Row k="Созданных репортов" v={String(detail.player.reports_created ?? detail.reports.length)}/><Row k="Анкет" v={String(detail.player.applications_count ?? detail.applications.length)}/>
            </div>}
            {tab==="applications"&&<div className="max-h-[650px] space-y-3 overflow-y-auto">{detail.applications.length ? detail.applications.map((app: Application)=><ApplicationCard key={app.id} app={app} telegramUsername={detail.player.telegram_username} telegramId={detail.player.telegram_id}/>) : <p className="py-4 text-sm text-moon-dim">Анкет нет.</p>}</div>}
            {tab==="moderation"&&<History items={detail.moderation} empty="История наказаний пуста." render={x=>`${x.type} · ${x.reason ?? "без причини"} · ${fmt(x.created_at)}`}/>}
            {tab==="reports"&&<History items={detail.reports} empty="Репортов нет." render={x=>`#${x.ticket_no ?? "—"} · ${x.type} · ${x.status} · ${fmt(x.created_at)}`}/>}
            {tab==="community"&&<div className="space-y-3"><Row k="Клан" v={detail.clan?.clans?.name ?? detail.player.clan_name ?? "—"}/><Row k="Роль в клане" v={detail.clan?.role ?? "—"}/><Row k="Голосований" v={String(detail.votes.length)}/><Row k="Достижений" v={String(detail.achievements.length)}/><Row k="Квестов" v={String(detail.quests.length)}/></div>}
            <div className="flex flex-wrap gap-2">
              <Link href={`/dashboard/support?user_id=${encodeURIComponent(detail.player.id)}`} className="flex-1 rounded-lg border border-border px-3 py-2.5 text-center text-sm text-moon-dim hover:text-moon">Написать игроку</Link>
              <Link href="/dashboard/moderation" className="flex-1 rounded-lg bg-ember/15 px-3 py-2.5 text-center text-sm text-ember hover:bg-ember/25">Открыть модерацию</Link>
            </div>
          </div>}
      </Card>
    </div>
  );
}
function Box({label,value}:{label:string;value:string}){return <div className="rounded-lg bg-panel-raised p-3"><p className="text-xs text-moon-dim">{label}</p><p className="mt-1 text-lg text-moon">{value}</p></div>}
function Row({k,v}:{k:string;v:string}){return <div className="flex justify-between gap-3 rounded-lg border border-border bg-panel-raised/40 px-3 py-2"><span className="text-moon-dim">{k}</span><span className="break-all text-right text-moon">{v}</span></div>}
function History<T extends { id: string | number }>({items,empty,render}:{items:T[];empty:string;render:(x:T)=>string}){return items.length?<div className="max-h-72 space-y-2 overflow-y-auto">{items.map(x=><div key={String(x.id)} className="rounded-lg border border-border bg-panel-raised/40 p-3 text-sm text-moon">{render(x)}</div>)}</div>:<p className="py-4 text-sm text-moon-dim">{empty}</p>}

function ApplicationCard({app,telegramUsername,telegramId}:{app:Application;telegramUsername:string|null;telegramId:number}) {
  return <div className="rounded-xl border border-border bg-panel-raised/30 p-4">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div><p className="font-mono text-xs text-curse">Анкета {app.application_no ? "#"+app.application_no : ""}</p><p className="mt-1 text-sm font-medium text-moon">{app.full_name ?? "Имя не указано"}</p><p className="text-xs text-moon-dim">{app.nickname ?? "Без ника"} · {app.platform ?? "Платформа не указана"}</p></div>
      <Badge tone={app.status==="ACCEPTED" ? "success" : app.status==="REJECTED" ? "danger" : "warn"}>{app.status==="ACCEPTED" ? "Принята" : app.status==="REJECTED" ? "Отклонена" : app.status==="PENDING" ? "На рассмотрении" : app.status}</Badge>
    </div>
    <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
      <Row k="Дата рождения" v={app.birth_date ?? "—"}/><Row k="Возраст" v={app.age != null ? String(app.age) : "—"}/><Row k="Источник" v={app.discovery_source ?? "—"}/><Row k="Подана" v={fmt(app.created_at)}/><Row k="Обновлена" v={fmt(app.updated_at)}/><Row k="Рассмотрена" v={fmt(app.reviewed_at)}/><Row k="Кто рассмотрел" v={app.reviewed_by_name ?? "—"}/><Row k="Telegram username" v={telegramUsername ? "@" + telegramUsername : "username не указан"}/><Row k="Telegram ID" v={String(telegramId)}/>
    </div>
    <div className="mt-3 grid grid-cols-1 gap-2"><TextBlock label="Цель" value={app.goal}/><TextBlock label="О себе" value={app.about}/>{app.rejection_reason&&<TextBlock label="Причина отказа" value={app.rejection_reason} danger/>}{app.staff_notes&&<TextBlock label="Внутренняя заметка" value={app.staff_notes}/>}</div>
  </div>;
}
function TextBlock({label,value,danger=false}:{label:string;value:string|null|undefined;danger?:boolean}) {
  return <div className={"rounded-lg border p-3 "+(danger?"border-danger/30 bg-danger/10":"border-border bg-panel-raised/40")}><p className={"text-xs "+(danger?"text-danger":"text-moon-dim")}>{label}</p><p className="mt-1 whitespace-pre-wrap break-words text-sm text-moon">{value||"—"}</p></div>;
}
