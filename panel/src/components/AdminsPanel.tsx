"use client";

import { STAFF_ROLE_LABELS } from "@prisma-eco/contracts";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Avatar, Badge, Card, SearchBar } from "@/components/ui";

type Admin = {
  id: string;
  user_id: string;
  created_at: string;
  users: {
    id: string;
    telegram_id: number;
    telegram_username: string | null;
    first_name: string | null;
    full_name: string | null;
    minecraft_nickname: string | null;
    status: string | null;
    is_whitelisted: boolean;
    is_banned: boolean;
    is_muted: boolean;
    rating: number | null;
    activity_score: number | null;
    last_seen_at: string | null;
  };
  roles: { id: string; name: string; description: string | null; priority: number } | { id: string; name: string; description: string | null; priority: number }[] | null;
};

const ROLES = ["owner", "head_admin", "head_staff", "admin", "senior_moderator", "moderator", "helper", "developer", "builder", "game_designer", "event_manager", "media", "content_maker"] as const;

function roleOf(admin: Admin) {
  return Array.isArray(admin.roles) ? admin.roles[0]?.name ?? null : admin.roles?.name ?? null;
}

function displayName(admin: Admin) {
  return admin.users.telegram_username ? `@${admin.users.telegram_username}` : admin.users.first_name ?? admin.users.full_name ?? String(admin.users.telegram_id);
}

export function AdminsPanel({ initialAdmins, canManage = false }: { initialAdmins: Admin[]; canManage?: boolean }) {
  const [admins, setAdmins] = useState(initialAdmins);
  const [search, setSearch] = useState("");
  const [telegramId, setTelegramId] = useState("");
  const [role, setRole] = useState<(typeof ROLES)[number]>("moderator");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return admins;
    return admins.filter((admin) => [displayName(admin), admin.users.minecraft_nickname, admin.users.full_name, admin.users.telegram_id, roleOf(admin)]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(q)));
  }, [admins, search]);

  async function addAdmin() {
    if (!/^\d+$/.test(telegramId.trim())) return setError("Telegram ID должен содержать только цифры.");
    setBusy(true); setError(null);
    const res = await fetch("/admin/api/admins", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ telegramId: telegramId.trim(), role }) });
    const data = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) return setError(data.error?.message ?? data.error ?? "Не удалось добавить администратора.");
    setTelegramId("");
    router.refresh();
  }

  async function changeRole(id: string, nextRole: string) {
    setBusy(true); setError(null);
    const res = await fetch("/admin/api/admins", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, role: nextRole }) });
    const data = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Не удалось изменить роль.");
    setAdmins((current) => current.map((admin) => admin.id === id ? { ...admin, roles: { ...(Array.isArray(admin.roles) ? admin.roles[0] : admin.roles!), id: Array.isArray(admin.roles) ? admin.roles[0]?.id ?? "" : admin.roles?.id ?? "", name: nextRole } } : admin));
    router.refresh();
  }

  async function removeAdmin(id: string) {
    setBusy(true); setError(null);
    const res = await fetch("/admin/api/admins", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
    const data = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Не удалось удалить администратора.");
    setAdmins((current) => current.filter((admin) => admin.id !== id));
  }

  return (
    <div className="space-y-4">
      {canManage && (
        <Card className="p-4">
          <div className="grid grid-cols-1 gap-2 md:grid-cols-[1fr_auto_auto_auto]">
            <SearchBar value={search} onChange={setSearch} placeholder="Имя, Telegram, Minecraft или роль…" />
            <input value={telegramId} onChange={(e) => setTelegramId(e.target.value.replace(/\D/g, ""))} placeholder="Telegram ID" className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse" />
            <select value={role} onChange={(e) => setRole(e.target.value as (typeof ROLES)[number])} className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none">
              {ROLES.map((item) => <option key={item} value={item}>{STAFF_ROLE_LABELS[item] ?? item}</option>)}
            </select>
            <button onClick={() => void addAdmin()} disabled={busy} className="rounded-lg bg-ember/15 px-4 py-2 text-sm font-medium text-ember hover:bg-ember/25 disabled:opacity-40">Добавить</button>
          </div>
        </Card>
      )}

      <div className="flex items-center justify-between gap-3">
        <SearchBar value={search} onChange={setSearch} placeholder="Поиск админа…" className="max-w-xl" />
        <span className="text-xs text-moon-dim">{visible.length} записей</span>
      </div>
      {error && <p className="rounded-lg border border-danger/30 bg-danger/10 px-3 py-2 text-xs text-danger">{error}</p>}

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        {visible.map((admin) => {
          const roleName = roleOf(admin) ?? "—";
          return (
            <Card key={admin.id} className="p-5">
              <div className="flex items-start gap-3">
                <Avatar name={displayName(admin)} size="lg" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-base font-medium text-moon">{displayName(admin)}</p>
                  <p className="truncate text-xs text-moon-dim">{admin.users.minecraft_nickname ?? "Без Minecraft-ника"} · Telegram {admin.users.telegram_id}</p>
                </div>
                <Badge tone={roleName === "owner" ? "curse" : roleName === "moderator" || roleName === "senior_moderator" || roleName === "head_staff" ? "success" : "neutral"}>{STAFF_ROLE_LABELS[roleName] ?? roleName}</Badge>
              </div>

              <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
                <div className="rounded-lg bg-panel-raised p-3"><p className="text-xs text-moon-dim">Рейтинг</p><p className="mt-1 text-lg text-moon">{admin.users.rating ?? 0}</p></div>
                <div className="rounded-lg bg-panel-raised p-3"><p className="text-xs text-moon-dim">Активность</p><p className="mt-1 text-lg text-moon">{admin.users.activity_score ?? 0}</p></div>
                <div className="rounded-lg bg-panel-raised p-3"><p className="text-xs text-moon-dim">Whitelist</p><p className="mt-1 text-sm text-moon">{admin.users.is_whitelisted ? "Да" : "Нет"}</p></div>
                <div className="rounded-lg bg-panel-raised p-3"><p className="text-xs text-moon-dim">Статус</p><p className="mt-1 text-sm text-moon">{admin.users.status ?? "—"}</p></div>
              </div>

              {canManage && (
                <div className="mt-4 flex flex-wrap gap-2">
                  <select value={roleName} onChange={(e) => void changeRole(admin.id, e.target.value)} disabled={busy || roleName === "owner"} className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-xs text-moon outline-none disabled:opacity-50">
                    {ROLES.map((item) => <option key={item} value={item}>{STAFF_ROLE_LABELS[item] ?? item}</option>)}
                  </select>
                  <button onClick={() => void removeAdmin(admin.id)} disabled={busy || roleName === "owner"} className="rounded-lg border border-danger/30 px-3 py-2 text-xs text-danger hover:bg-danger/10 disabled:opacity-40">Удалить доступ</button>
                </div>
              )}
            </Card>
          );
        })}
        {visible.length === 0 && <Card className="p-10 text-center text-sm text-moon-dim xl:col-span-2">Администраторы не найдены.</Card>}
      </div>
    </div>
  );
}
