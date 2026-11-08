"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Card } from "@/components/Card";
import { Icon } from "@/components/Icon";

type Player = {
  id:string; minecraft_nickname:string; telegram_username?:string|null; platform?:string|null;
  rating?:number|null; activity_score?:number|null; level?:number|null; xp?:number|null;
  last_seen_at?:string|null; created_at?:string|null; clan_id?:string|null;
};

const ONLINE_MS=120000;
const SORTS=[
  ["rating","Рейтинг"],
  ["activity","Активность"],
  ["level","Уровень"],
  ["xp","XP"],
  ["online","Онлайн"],
  ["new","Новые"],
] as const;

export function PlayersDirectory({players,currentUserId}:{players:Player[];currentUserId:string}) {
  const [query,setQuery]=useState("");
  const [sort,setSort]=useState("rating");
  const [onlineOnly,setOnlineOnly]=useState(false);
  const now=Date.now();
  const online=(p:Player)=>Boolean(p.last_seen_at && now-new Date(p.last_seen_at).getTime()<ONLINE_MS);

  const filtered=useMemo(()=>{
    const q=query.trim().toLowerCase();
    return players.slice()
      .filter(p=>!q || p.minecraft_nickname.toLowerCase().includes(q) || String(p.telegram_username||"").toLowerCase().includes(q))
      .filter(p=>!onlineOnly || online(p))
      .sort((a,b)=>{
        if(sort==="online") return Number(online(b))-Number(online(a)) || (b.rating||0)-(a.rating||0);
        if(sort==="new") return new Date(b.created_at||0).getTime()-new Date(a.created_at||0).getTime();
        const av=sort==="activity"?a.activity_score||0:sort==="level"?a.level||0:sort==="xp"?a.xp||0:a.rating||0;
        const bv=sort==="activity"?b.activity_score||0:sort==="level"?b.level||0:sort==="xp"?b.xp||0:b.rating||0;
        return bv-av;
      });
  },[players,query,sort,onlineOnly]);

  return (
    <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-[var(--primary)]">COMMUNITY</p><h1 className="mt-1 text-3xl font-semibold">Игроки</h1><p className="mt-1 text-sm text-[var(--muted-foreground)]">Все участники PRISMA, их Telegram и текущая активность.</p></div>
        <div className="prisma-glass-surface rounded-2xl border px-4 py-3 text-right"><p className="text-2xl font-semibold">{players.filter(online).length}</p><p className="text-xs text-[var(--muted-foreground)]">сейчас активны</p></div>
      </div>

      <div className="mt-5 grid gap-3 md:grid-cols-[1fr_190px_auto]">
        <label className="relative"><Icon name="search" size={15} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted-foreground)]"/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Ник Minecraft или @username" className="prisma-glass-control h-11 w-full rounded-xl border pl-9 pr-4 text-sm outline-none focus:border-[var(--primary)]/50"/></label>
        <select value={sort} onChange={e=>setSort(e.target.value)} className="prisma-glass-control h-11 rounded-xl border px-3 text-sm">{SORTS.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select>
        <button type="button" onClick={()=>setOnlineOnly(v=>!v)} className={"prisma-glass-control h-11 rounded-xl border px-4 text-sm font-medium "+(onlineOnly?"border-[var(--primary)]/50 bg-[rgba(113,225,172,.10)]":"hover:bg-white/[0.055]")}>
          {onlineOnly?"Только активные":"Все игроки"}
        </button>
      </div>

      <div className="prisma-glass-surface mt-5 overflow-hidden rounded-2xl border">
        <div className="hidden grid-cols-[52px_minmax(0,1.6fr)_minmax(120px,.9fr)_100px_110px] gap-3 border-b bg-[var(--muted)] px-5 py-3 text-[11px] font-semibold uppercase tracking-wide text-[var(--muted-foreground)] md:grid"><span>#</span><span>Игрок</span><span>Telegram</span><span>Рейтинг</span><span>Статус</span></div>
        <div className="divide-y">
          {filtered.map((p,i)=>{
            const isOnline=online(p),me=p.id===currentUserId;
            return <Link key={p.id} href={"/app/players/"+encodeURIComponent(p.minecraft_nickname)} className={"block px-4 py-4 transition hover:bg-[var(--muted)] sm:px-5 "+(me?"bg-[rgba(113,225,172,.08)] shadow-[inset_3px_0_0_var(--primary)]":"")}>
              <div className="grid gap-2 md:grid-cols-[52px_minmax(0,1.6fr)_minmax(120px,.9fr)_100px_110px] md:items-center md:gap-3">
                <span className="hidden text-sm font-semibold text-[var(--muted-foreground)] md:block">#{i+1}</span>
                <div className="min-w-0"><div className="flex items-center gap-2"><span className={"size-2 shrink-0 rounded-full "+(isOnline?"bg-[var(--primary)] shadow-[0_0_8px_rgba(113,225,172,.7)]":"bg-[var(--border)]")}/><span className="truncate font-semibold">{p.minecraft_nickname}</span>{me&&<span className="rounded-full bg-[var(--primary)] px-2 py-0.5 text-[10px] font-bold text-[var(--primary-foreground)]">Вы</span>}</div><p className="mt-1 text-xs text-[var(--muted-foreground)]">{p.platform||"—"} · уровень {p.level||1} · {p.activity_score||0} activity</p></div>
                <span className="text-sm text-[var(--muted-foreground)]">{p.telegram_username?"@"+p.telegram_username:"—"}</span>
                <span className="text-sm font-semibold">{p.rating||0} RR</span>
                <span className={"text-xs font-medium "+(isOnline?"text-[var(--primary)]":"text-[var(--muted-foreground)]")}>{isOnline?"Активен":"Не в сети"}</span>
              </div>
            </Link>
          })}
          {!filtered.length&&<div className="px-6 py-14 text-center text-sm text-[var(--muted-foreground)]">Игроков по этому фильтру не найдено.</div>}
        </div>
      </div>
      <p className="mt-3 text-xs text-[var(--muted-foreground)]">Активный игрок — последний сигнал активности не старше двух минут.</p>
    </div>
  );
}
