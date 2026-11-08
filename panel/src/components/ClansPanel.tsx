"use client";

import { formatDateTime } from "@prisma-eco/shared";

import { CLAN_ENTITY_STATUS_LABELS, CLAN_ROLE_LABELS, CLAN_TYPE_LABELS } from "@prisma-eco/contracts";
import { useState } from "react";
import { Avatar, Badge, Card } from "@/components/ui";
import { Modal } from "@/components/Modal";

export type ClanOwner = { minecraft_nickname: string | null; telegram_username: string | null };
export type Clan = {
  id: string; name: string; tag: string; rating: number; description: string | null; type: string; status: string;
  level: number; xp: number; wins: number; losses: number; color: string | null; avatar_url: string | null;
  created_at: string; owner: ClanOwner | ClanOwner[] | null;
};
type ClanMember = {
  user_id: string;
  role: string;
  status: string;
  nickname?: string | null;
  users?: { minecraft_nickname: string | null; full_name: string | null } | null;
};
type ActivityEntry = { id?: string | number; kind?: string | null; xp?: number | null; created_at: string };
type WarEntry = { id?: string | number; status?: string | null; score_a?: number | null; score_b?: number | null; created_at: string };
type InvitationEntry = { id?: string | number; status?: string | null; created_at: string };
type AnnouncementEntry = { id?: string | number; title?: string | null; created_at: string };
export type ClanDetail = { clan: Clan; members: ClanMember[]; activity: ActivityEntry[]; invitations: InvitationEntry[]; wars: WarEntry[]; announcements: AnnouncementEntry[] };

export function ClansPanel({ initialClans, initialDetails }: { initialClans: Clan[]; initialDetails: Record<string, Omit<ClanDetail, "clan">> }) {
  const [selected, setSelected] = useState<ClanDetail | null>(null);
  const [targetUserId, setTargetUserId] = useState("");
  const [targetRole, setTargetRole] = useState("");
  const [roleBusy, setRoleBusy] = useState(false);
  const [roleMessage, setRoleMessage] = useState<string | null>(null);
  const [roleError, setRoleError] = useState<string | null>(null);

  function openClan(detail: ClanDetail | null) {
    setSelected(detail);
    setRoleMessage(null);
    setRoleError(null);
    const first = detail?.members?.find((member) => member.role !== "owner");
    setTargetUserId(first?.user_id ?? "");
    setTargetRole("");
  }

  async function updateRole() {
    if (!selected || !targetUserId || !targetRole) return;
    setRoleBusy(true);
    setRoleError(null);
    setRoleMessage(null);
    try {
      const response = await fetch("/admin/api/clans/member-role", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_user_id: targetUserId, role: targetRole }),
      });
      const payload = await response.json().catch(() => ({})) as { error?: string; result?: { role?: string } };
      if (!response.ok) {
        setRoleError(payload.error ?? "Не удалось изменить роль.");
        return;
      }
      const updated = payload.result;
      setSelected((current) => {
        if (!current) return current;
        return {
          ...current,
          members: current.members.map((member) =>
            member.user_id === targetUserId ? { ...member, role: updated?.role ?? targetRole } : member,
          ),
        };
      });
      setRoleMessage("Роль игрока обновлена.");
    } catch {
      setRoleError("Не удалось связаться с PRISMA.");
    } finally {
      setRoleBusy(false);
    }
  }
  return <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
    {initialClans.map((clan) => {
      const owner = Array.isArray(clan.owner) ? clan.owner[0] : clan.owner;
      const d = initialDetails[clan.id];
      return <button key={clan.id} onClick={() => openClan(d ? { clan, ...d } : null)} className="block w-full min-w-0 text-left">
        <Card className="h-full p-5 transition-colors hover:border-white/20">
          <div className="flex min-w-0 items-start justify-between gap-3">
            <div className="min-w-0"><p className="truncate font-mono text-xs uppercase tracking-wide text-curse">{clan.tag}</p><h2 className="truncate font-display text-lg text-moon">{clan.name}</h2></div>
            <div className="flex max-w-[55%] shrink-0 flex-wrap justify-end gap-1"><Badge>{CLAN_TYPE_LABELS[clan.type] ?? clan.type}</Badge><Badge tone={clan.status === "active" ? "success" : "warn"}>{CLAN_ENTITY_STATUS_LABELS[clan.status] ?? clan.status}</Badge></div>
          </div>
          {clan.description && <p className="mt-3 line-clamp-3 text-sm text-moon-dim">{clan.description}</p>}
          <div className="mt-4 grid grid-cols-4 gap-2 text-xs"><Stat label="★" value={String(clan.rating)} /><Stat label="LVL" value={String(clan.level)} /><Stat label="W" value={String(clan.wins)} /><Stat label="L" value={String(clan.losses)} /></div>
          <div className="mt-4 flex min-w-0 items-center gap-2 border-t border-border pt-4"><Avatar name={owner?.minecraft_nickname ?? "?"} size="sm"/><div className="min-w-0 flex-1"><p className="truncate text-sm text-moon">{owner?.minecraft_nickname ?? "—"}</p><p className="truncate text-xs text-moon-dim">{owner?.telegram_username ? "@" + owner.telegram_username : "лидер"}</p></div><span className="ml-auto text-xs text-primary">Открыть →</span></div>
        </Card>
      </button>;
    })}
    {initialClans.length===0 && <Card className="p-10 text-center text-sm text-moon-dim sm:col-span-2 lg:col-span-3">Пока ни одного клана не создано.</Card>}
    <Modal open={!!selected} onClose={() => setSelected(null)}>
      {selected && <div className="max-h-[85vh] space-y-5 overflow-y-auto">
        <div className="flex items-start gap-3"><Avatar name={selected.clan.name} size="lg"/><div className="min-w-0"><p className="font-mono text-xs uppercase tracking-wider text-curse">[{selected.clan.tag}]</p><h2 className="font-display text-2xl text-moon">{selected.clan.name}</h2><p className="text-sm text-moon-dim">{selected.clan.description ?? "Без описания"}</p></div></div>
        <section className="rounded-lg border border-border bg-panel-raised/40 p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 className="text-sm font-medium text-moon">Управление ролями</h3>
              <p className="mt-1 text-xs text-moon-dim">Администратор с правом управления кланами может менять роль любого участника, кроме владельца.</p>
            </div>
          </div>
          {roleError && <div className="mt-3 rounded-md border border-danger/30 bg-danger/10 px-3 py-2 text-xs text-danger">{roleError}</div>}
          {roleMessage && <div className="mt-3 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{roleMessage}</div>}
          <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_180px_auto]">
            <select
              value={targetUserId}
              onChange={(event) => setTargetUserId(event.target.value)}
              className="h-9 rounded-md border bg-background px-3 text-sm"
            >
              <option value="">Выберите участника</option>
              {selected.members.filter((member) => member.role !== "owner").map((member) => (
                <option key={member.user_id} value={member.user_id}>
                  {member.users?.minecraft_nickname ?? member.nickname ?? "Игрок"}
                </option>
              ))}
            </select>
            <select
              value={targetRole}
              onChange={(event) => setTargetRole(event.target.value)}
              className="h-9 rounded-md border bg-background px-3 text-sm"
            >
              <option value="">Новая роль</option>
              <option value="co_owner">Совладелец</option>
              <option value="officer">Офицер</option>
              <option value="member">Участник</option>
              <option value="recruit">Рекрут</option>
            </select>
            <button
              type="button"
              onClick={() => void updateRole()}
              disabled={roleBusy || !targetUserId || !targetRole}
              className="h-9 rounded-md bg-primary px-3 text-sm font-medium text-primary-foreground disabled:cursor-not-allowed disabled:opacity-50"
            >
              {roleBusy ? "Сохраняю…" : "Изменить"}
            </button>
          </div>
        </section>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-5"><Stat label="Рейтинг" value={String(selected.clan.rating)}/><Stat label="Уровень" value={String(selected.clan.level)}/><Stat label="XP" value={String(selected.clan.xp)}/><Stat label="Победы" value={String(selected.clan.wins)}/><Stat label="Поражения" value={String(selected.clan.losses)}/></div>
        <Section title={"Участники · " + selected.members.length}><div className="space-y-1">{selected.members.map((m)=><div key={m.user_id} className="flex items-center justify-between rounded-lg border border-border bg-panel-raised/40 px-3 py-2 text-sm"><span>{m.users?.minecraft_nickname ?? m.users?.full_name ?? "Игрок"}</span><span className="text-xs text-moon-dim">{CLAN_ROLE_LABELS[String(m.role) as keyof typeof CLAN_ROLE_LABELS] ?? String(m.role)} · {CLAN_ENTITY_STATUS_LABELS[m.status] ?? m.status}</span></div>)}{!selected.members.length&&<p className="text-sm text-moon-dim">Участников нет.</p>}</div></Section>
        <Section title="История активности"><History items={selected.activity} render={(x)=>String(x.kind ?? "событие") + " · +" + String(x.xp ?? 0) + " XP · " + formatDateTime(x.created_at)}/></Section>
        <Section title="Войны"><History items={selected.wars} render={(x)=>(CLAN_ENTITY_STATUS_LABELS[String(x.status)] ?? String(x.status)) + " · " + String(x.score_a) + ":" + String(x.score_b) + " · " + formatDateTime(x.created_at)}/></Section>
        <Section title="Приглашения"><History items={selected.invitations} render={(x)=>(CLAN_ENTITY_STATUS_LABELS[String(x.status)] ?? String(x.status)) + " · " + formatDateTime(x.created_at)}/></Section>
        <Section title="Объявления"><History items={selected.announcements} render={(x)=>String(x.title) + " · " + formatDateTime(x.created_at)}/></Section>
      </div>}
    </Modal>
  </div>;
}
function Stat({label,value}:{label:string;value:string}){return <div className="rounded-lg bg-panel-raised p-2.5 text-center"><p className="text-[10px] uppercase tracking-wide text-moon-dim">{label}</p><p className="mt-1 font-mono text-sm text-moon">{value}</p></div>}
function Section({title,children}:{title:string;children:React.ReactNode}){return <section><h3 className="mb-2 text-sm font-medium text-moon">{title}</h3>{children}</section>}
function History<T extends { id?: string | number; created_at: string }>({items,render}:{items:T[];render:(x:T)=>string}){return items.length?<div className="max-h-48 space-y-1 overflow-y-auto">{items.map(x=><div key={String(x.id ?? x.created_at)} className="rounded-lg border border-border bg-panel-raised/40 px-3 py-2 text-xs text-moon">{render(x)}</div>)}</div>:<p className="text-sm text-moon-dim">Нет записей.</p>}