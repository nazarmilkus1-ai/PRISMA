"use client";

import { formatDateTime } from "@prisma-eco/shared";
import { useEffect, useState } from "react";
import { Avatar, Badge, Card, ModerationBadge, SearchBar } from "@/components/ui";
import { ConfirmModal } from "@/components/Modal";

type SearchResult = {
  id: string;
  minecraft_nickname: string | null;
  telegram_username: string | null;
  status: string;
  is_whitelisted: boolean;
  is_banned: boolean;
  is_muted: boolean;
};
type LogType = "WARN" | "MUTE" | "KICK" | "BAN" | "UNMUTE" | "UNBAN" | "WHITELIST" | "UNWHITELIST";
type ActionType = "WARN" | "MUTE" | "KICK" | "BAN" | "UNMUTE" | "UNBAN" | "WHITELIST" | "UNWHITELIST";
type LogEntry = {
  id: string;
  type: LogType;
  reason: string;
  duration_minutes: number | null;
  expires_at: string | null;
  source: string;
  issued_by_name: string | null;
  created_at: string;
  revoked: boolean;
  revoked_at: string | null;
  revoked_by_name: string | null;
};
type PlayerDetail = {
  user: SearchResult & {
    telegram_id: number;
    rating: number;
    activity_score: number;
    muted_until: string | null;
    last_seen_at: string | null;
  };
  logs: LogEntry[];
};

const ACTION_LABELS: Record<ActionType, string> = {
  WARN: "Варн",
  MUTE: "Мут",
  KICK: "Кик / снять whitelist",
  BAN: "Бан",
  UNMUTE: "Снять мут",
  UNBAN: "Снять бан",
  WHITELIST: "Выдать whitelist",
  UNWHITELIST: "Снять whitelist",
};

export function ModerationPanel() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [selected, setSelected] = useState<PlayerDetail | null>(null);
  const [actionType, setActionType] = useState<ActionType>("WARN");
  const [reason, setReason] = useState("");
  const [duration, setDuration] = useState(120);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [revokingId, setRevokingId] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  async function loadPlayers(search = "") {
    const res = await fetch(`/admin/api/moderation${search ? `?search=${encodeURIComponent(search)}` : ""}`);
    if (!res.ok) return setLoadError("Не удалось загрузить список игроков.");
    setLoadError(null);
    setResults((await res.json()).users ?? []);
  }

  useEffect(() => { loadPlayers(); }, []);
  useEffect(() => {
    const handle = setTimeout(() => loadPlayers(query.trim()), 250);
    return () => clearTimeout(handle);
  }, [query]);

  async function loadPlayer(id: string) {
    const res = await fetch(`/admin/api/moderation/${id}`);
    if (res.ok) setSelected(await res.json());
  }

  async function submitAction() {
    if (!selected || !reason.trim()) return;
    setBusy(true);
    const res = await fetch("/admin/api/moderation", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: selected.user.id,
        type: actionType,
        reason: reason.trim(),
        durationMinutes: actionType === "MUTE" || actionType === "BAN" ? duration : undefined,
      }),
    });
    setBusy(false);
    if (!res.ok) {
      setLoadError("Не удалось применить действие. Проверьте права и Supabase.");
      return;
    }
    setReason("");
    setConfirmOpen(false);
    await loadPlayers(query.trim());
    await loadPlayer(selected.user.id);
  }

  async function revokeLog(logId: string) {
    if (!selected) return;
    setRevokingId(logId);
    const res = await fetch(`/admin/api/moderation/logs/${logId}`, { method: "POST" });
    setRevokingId(null);
    if (!res.ok) return setLoadError("Не удалось отменить действие.");
    await loadPlayer(selected.user.id);
  }

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
      <Card className="p-4">
        <SearchBar value={query} onChange={setQuery} placeholder="Minecraft-ник или Telegram…" />
        {loadError && <p className="mt-3 rounded-lg border border-danger/30 bg-danger/10 px-3 py-2 text-xs text-danger">{loadError}</p>}
        <div className="mt-3 max-h-[65vh] space-y-1 overflow-y-auto pr-1">
          {results.map((u) => (
            <button
              key={u.id}
              onClick={() => loadPlayer(u.id)}
              className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm transition-colors ${selected?.user.id === u.id ? "bg-panel-raised text-moon" : "text-moon-dim hover:bg-panel-raised/60"}`}
            >
              <span className="flex min-w-0 items-center gap-2">
                <Avatar name={u.minecraft_nickname ?? u.telegram_username ?? "?"} size="sm" />
                <span className="min-w-0">
                  <span className="block truncate font-mono">{u.minecraft_nickname ?? "Без Minecraft-ника"}</span>
                  {u.telegram_username && <span className="block truncate text-xs text-moon-dim">@{u.telegram_username}</span>}
                </span>
              </span>
              <span className="ml-2 flex shrink-0 gap-1 text-xs">
                {u.is_banned && <span className="text-danger">бан</span>}
                {u.is_muted && <span className="text-warn">мут</span>}
                {u.is_whitelisted && <span className="text-success">✓</span>}
              </span>
            </button>
          ))}
          {results.length === 0 && <p className="px-3 py-4 text-sm text-moon-dim">Игроков пока нет.</p>}
        </div>
      </Card>

      <Card className="p-4 sm:p-5">
        {!selected ? (
          <p className="text-sm text-moon-dim">Выберите игрока слева, чтобы увидеть профиль и историю.</p>
        ) : (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              <Avatar name={selected.user.minecraft_nickname ?? "?"} size="lg" />
              <div className="min-w-0">
                <h3 className="truncate font-mono text-lg text-moon">{selected.user.minecraft_nickname ?? "Без Minecraft-ника"}</h3>
                <p className="text-xs text-moon-dim">
                  {selected.user.telegram_username ? `@${selected.user.telegram_username}` : selected.user.telegram_id} · рейтинг {selected.user.rating} · активность {selected.user.activity_score}
                </p>
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <Badge tone={selected.user.is_banned ? "danger" : selected.user.is_muted ? "warn" : selected.user.is_whitelisted ? "success" : "neutral"}>
                {selected.user.is_banned ? "Бан" : selected.user.is_muted ? "Мут" : selected.user.is_whitelisted ? "Whitelist" : "Не в whitelist"}
              </Badge>
              <span className="text-xs text-moon-dim">Статус заявки: {selected.user.status}</span>
            </div>

            <div className="rounded-lg border border-border bg-panel-raised p-3">
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-[auto_auto_minmax(0,1fr)_auto]">
                <select
                  value={actionType}
                  onChange={(e) => setActionType(e.target.value as ActionType)}
                  className="rounded-md border border-border bg-panel px-2 py-2 text-sm text-moon outline-none"
                >
                  {Object.entries(ACTION_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
                {(actionType === "MUTE" || actionType === "BAN") && (
                  <input
                    type="number"
                    min={1}
                    value={duration}
                    onChange={(e) => setDuration(Number(e.target.value))}
                    aria-label="Длительность в минутах"
                    className="rounded-md border border-border bg-panel px-2 py-2 text-sm text-moon outline-none"
                  />
                )}
                <input
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Причина обязательна"
                  className="min-w-0 rounded-md border border-border bg-panel px-2 py-2 text-sm text-moon outline-none focus:border-curse"
                />
                <button
                  onClick={() => setConfirmOpen(true)}
                  disabled={!reason.trim()}
                  className="rounded-md bg-ember/20 px-3 py-2 text-sm font-medium text-ember transition-colors hover:bg-ember/30 disabled:opacity-40"
                >
                  Применить
                </button>
              </div>
            </div>

            <div className="space-y-2">
              {selected.logs.length === 0 && <p className="text-sm text-moon-dim">История пуста.</p>}
              {selected.logs.map((log) => {
                const canRevoke =
                  !log.revoked &&
                  ((log.type === "WARN") ||
                    (log.type === "MUTE" && selected.user.is_muted) ||
                    (log.type === "BAN" && selected.user.is_banned));
                return (
                  <div key={log.id} className={`flex items-start gap-3 rounded-lg border border-border px-3 py-2 text-sm ${log.revoked ? "opacity-50" : ""}`}>
                    <ModerationBadge type={log.type} />
                    <div className="min-w-0 flex-1">
                      <p className="text-moon">
                        {log.reason}
                        {log.revoked && <span className="ml-2 text-xs text-success">отменено</span>}
                      </p>
                      <p className="text-xs text-moon-dim">
                        {formatDateTime(log.created_at)}
                        {log.issued_by_name ? ` · ${log.issued_by_name}` : ""}
                        {log.duration_minutes ? ` · ${log.duration_minutes} мин.` : ""}
                        {log.revoked && log.revoked_by_name ? ` · снял: ${log.revoked_by_name}` : ""}
                      </p>
                    </div>
                    {canRevoke && (
                      <button
                        onClick={() => revokeLog(log.id)}
                        disabled={revokingId === log.id}
                        className="shrink-0 rounded-md bg-panel-raised px-2.5 py-1 text-xs text-moon-dim hover:bg-success/20 hover:text-success"
                      >
                        {revokingId === log.id
                          ? "…"
                          : log.type === "WARN"
                            ? "Отменить варн"
                            : log.type === "BAN"
                              ? "Снять бан"
                              : "Снять мут"}
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </Card>

      <ConfirmModal
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        onConfirm={submitAction}
        title={`${ACTION_LABELS[actionType]}: ${selected?.user.minecraft_nickname ?? ""}`}
        description={`Причина: ${reason}`}
        confirmLabel="Применить"
        tone={actionType === "KICK" || actionType === "BAN" ? "danger" : actionType === "UNMUTE" || actionType === "UNBAN" ? "success" : "ember"}
        busy={busy}
      />
    </div>
  );
}
