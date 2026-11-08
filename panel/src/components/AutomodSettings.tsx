"use client";

import { useEffect, useMemo, useState } from "react";
import { fetchJson } from "@prisma-eco/shared";
import { Alert, Card, ToggleSwitch } from "@/components/ui";

type Action = "off" | "warn" | "mute" | "ban";

type ChatSettings = {
  chat_id: string | number;
  anti_links: boolean;
  anti_caps: boolean;
  anti_flood: boolean;
  anti_media: boolean;
  anti_profanity: boolean;
  anti_mentions?: boolean;
  anti_raid?: boolean;
  caps_threshold?: number;
  flood_messages?: number;
  flood_window_seconds?: number;
  links_action?: Action;
  caps_action?: Action;
  flood_action?: Action;
  profanity_action?: Action;
  media_action?: Action;
  repeat_warn_action?: Action;
};

const TOGGLES = [
  { key: "anti_links" as const, label: "Ссылки", description: "Блокирует опасные/нежелательные URL." },
  { key: "anti_caps" as const, label: "CAPS", description: "Выявляет чрезмерное использование верхнего регистра." },
  { key: "anti_flood" as const, label: "Флуд", description: "Ограничивает серии сообщений за короткий промежуток времени." },
  { key: "anti_media" as const, label: "GIF / стикеры", description: "Контролирует GIF и стикеры." },
  { key: "anti_profanity" as const, label: "Ненормативная лексика", description: "Проверяет сообщения по словарю." },
  { key: "anti_mentions" as const, label: "Упоминания", description: "Контролирует массовые @упоминания." },
  { key: "anti_raid" as const, label: "Рейды", description: "Снижает риск массового входа/спама." },
];

const ACTIONS: { value: Action; label: string }[] = [
  { value: "off", label: "Выключено" },
  { value: "warn", label: "Предупреждение" },
  { value: "mute", label: "Mute" },
  { value: "ban", label: "Ban" },
];

const EMPTY_NEW: Omit<ChatSettings, "chat_id"> = {
  anti_links: true,
  anti_caps: true,
  anti_flood: true,
  anti_media: true,
  anti_profanity: true,
  anti_mentions: false,
  anti_raid: false,
  caps_threshold: 70,
  flood_messages: 5,
  flood_window_seconds: 8,
  links_action: "warn",
  caps_action: "warn",
  flood_action: "mute",
  profanity_action: "warn",
  media_action: "off",
  repeat_warn_action: "mute",
};

function actionKey(key: string) {
  const mapping: Record<string, keyof ChatSettings> = {
    anti_links: "links_action",
    anti_caps: "caps_action",
    anti_flood: "flood_action",
    anti_media: "media_action",
    anti_profanity: "profanity_action",
  };
  return mapping[key];
}

export function AutomodSettings() {
  const [chats, setChats] = useState<ChatSettings[] | null>(null);
  const [newChatId, setNewChatId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState<string | null>(null);
  const [verification, setVerification] = useState<Record<string, { state: "loading" | "ok" | "error"; message: string; bot?: string; permissions?: string[] }>>({});

  async function load() {
    setError(null);
    try {
      const { response: res, data } = await fetchJson<{ error?: string; chats?: ChatSettings[] }>("/admin/api/chat-settings", { cache: "no-store" });
      if (!res.ok) throw new Error(data.error ?? "Не удалось загрузить настройки чатов.");
      setChats(data.chats ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось загрузить настройки чатов.");
      setChats([]);
    }
  }

  useEffect(() => { void load(); }, []);

  async function save(settings: ChatSettings) {
    setSaving(String(settings.chat_id));
    setError(null);
    try {
      const res = await fetch("/admin/api/chat-settings", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error?.message ?? data.error ?? "Не удалось сохранить настройки.");
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось сохранить настройки.");
    } finally {
      setSaving(null);
    }
  }

  async function verifyChat(chatId: string | number) {
    const key = String(chatId);
    setVerification((v) => ({ ...v, [key]: { state: "loading", message: "Проверяем Telegram…" } }));
    const res = await fetch("/admin/api/chat-settings/verify", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ chat_id: key }) });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data.ok || data.is_admin === false) {
      setVerification((v) => ({ ...v, [key]: { state: "error", message: data.error ?? "У бота нет прав администратора.", bot: data.bot?.username ? `@${data.bot.username}` : undefined } }));
      return;
    }
    const perms = ["delete_messages","restrict_members","invite_users"].filter((p) => Boolean(data.membership?.[`can_${p}`]));
    setVerification((v) => ({ ...v, [key]: { state: "ok", message: `${data.chat?.title ?? "Чат"} · ${data.membership?.status}`, bot: data.bot?.username ? `@${data.bot.username}` : data.bot?.name, permissions: perms } }));
  }

  async function removeChat(chatId: string | number) {
    setSaving(String(chatId));
    setError(null);
    try {
      const res = await fetch("/admin/api/chat-settings", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: String(chatId) }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error?.message ?? data.error ?? "Не удалось удалить чат.");
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось удалить чат.");
    } finally {
      setSaving(null);
    }
  }

  function addChat() {
    const trimmed = newChatId.trim();
    if (!/^-?\d{5,20}$/.test(trimmed)) {
      setError("Введите корректный числовой ID Telegram-чата, например -1001234567890.");
      return;
    }
    void save({ chat_id: trimmed, ...EMPTY_NEW });
    setNewChatId("");
  }

  const configuredCount = useMemo(() => chats?.length ?? 0, [chats]);

  return (
    <div className="space-y-4">
      <Card className="p-5">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h3 className="font-medium text-moon">Telegram-автомодерация</h3>
            <p className="mt-1 max-w-2xl text-sm text-moon-dim">
              Добавляйте группы отдельно. Настройки каждого чата сохраняются в БД и не влияют на другие группы.
            </p>
          </div>
          <div className="rounded-lg border border-border bg-panel-raised px-3 py-2 text-xs text-moon-dim">
            Настроено групп: <span className="font-medium text-moon">{configuredCount}</span>
          </div>
        </div>

        <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto]">
          <input
            value={newChatId}
            onChange={(e) => setNewChatId(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") addChat(); }}
            inputMode="numeric"
            placeholder="ID чату, напр. -1001234567890"
            className="min-w-0 rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse"
          />
          <button onClick={addChat} disabled={!newChatId.trim()} className="rounded-lg bg-ember/20 px-5 py-2.5 text-sm font-medium text-ember transition-colors hover:bg-ember/30 disabled:cursor-not-allowed disabled:opacity-40">
            Добавить группу
          </button>
        </div>
        <p className="mt-2 text-xs text-moon-dim">После добавления можно отдельно настроить правила и уровни наказаний.</p>
        {error && <div className="mt-3"><Alert variant="destructive">{error}</Alert></div>}
      </Card>

      {chats === null ? (
        <Card className="p-5"><p className="text-sm text-moon-dim">Загрузка настроек…</p></Card>
      ) : chats.length === 0 ? (
        <Card className="p-6 text-center">
          <p className="font-medium text-moon">Нет подключённых групп</p>
          <p className="mt-1 text-sm text-moon-dim">Введите ID группы выше, чтобы создать её профиль автомодерации.</p>
        </Card>
      ) : chats.map((chat) => (
        <Card key={chat.chat_id} className="overflow-hidden">
          <div className="border-b border-border px-5 py-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="font-mono text-sm text-moon">{chat.chat_id}</p>
                <p className="mt-1 text-xs text-moon-dim">Настройки этой группы</p>{verification[String(chat.chat_id)] && <div className={`mt-2 rounded-lg border px-3 py-2 text-xs ${verification[String(chat.chat_id)]?.state === "ok" ? "border-success/30 bg-success/10 text-success" : verification[String(chat.chat_id)]?.state === "error" ? "border-danger/30 bg-danger/10 text-danger" : "border-border text-moon-dim"}`}><p>{verification[String(chat.chat_id)]?.message}</p>{verification[String(chat.chat_id)]?.bot && <p className="mt-1">Бот: {verification[String(chat.chat_id)]?.bot}</p>}{verification[String(chat.chat_id)]?.permissions?.length ? <p className="mt-1">Права: {verification[String(chat.chat_id)]?.permissions?.join(", ")}</p> : null}</div>}
              </div>
              <div className="flex flex-wrap gap-2">
                <button onClick={() => void verifyChat(chat.chat_id)} disabled={verification[String(chat.chat_id)]?.state === "loading"} className="rounded-md border border-success/30 px-3 py-1.5 text-xs text-success transition-colors hover:bg-success/10 disabled:opacity-40">
                  {verification[String(chat.chat_id)]?.state === "loading" ? "Проверяем…" : "Проверить бота"}
                </button>
                <button onClick={() => void removeChat(chat.chat_id)} disabled={saving === String(chat.chat_id)} className="rounded-md border border-danger/30 px-3 py-1.5 text-xs text-danger transition-colors hover:bg-danger/10 disabled:opacity-40">
                  {saving === String(chat.chat_id) ? "Сохраняю…" : "Удалить группу"}
                </button>
              </div>
            </div>
          </div>

          <div className="space-y-5 p-5">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {TOGGLES.map((toggle) => (
                <div key={toggle.key} className="rounded-xl border border-border bg-panel-raised/40 p-3">
                  <ToggleSwitch
                    label={toggle.label}
                    checked={Boolean(chat[toggle.key])}
                    disabled={saving === String(chat.chat_id)}
                    onChange={(value) => void save({ ...chat, [toggle.key]: value })}
                  />
                  <p className="mt-1 pl-0 text-xs text-moon-dim">{toggle.description}</p>
                  {actionKey(toggle.key) && (
                    <select
                      value={String(chat[actionKey(toggle.key)!] ?? "off")}
                      disabled={saving === String(chat.chat_id) || !chat[toggle.key]}
                      onChange={(e) => void save({ ...chat, [actionKey(toggle.key)!]: e.target.value as Action })}
                      className="mt-3 w-full rounded-lg border border-border bg-panel px-3 py-2 text-xs text-moon outline-none disabled:opacity-40"
                    >
                      {ACTIONS.map((option) => <option key={option.value} value={option.value}>{option.value === "off" && toggle.key === "anti_flood" ? "Удалить без наказания" : option.label}</option>)}
                    </select>
                  )}
                </div>
              ))}
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <label className="text-xs text-moon-dim">Порог CAPS (%)<input type="number" min={50} max={100} value={chat.caps_threshold ?? 70} onChange={(e) => void save({ ...chat, caps_threshold: Math.min(100, Math.max(50, Number(e.target.value) || 70)) })} className="mt-1 w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon" /></label>
              <label className="text-xs text-moon-dim">Флуд: сообщений<input type="number" min={2} max={30} value={chat.flood_messages ?? 5} onChange={(e) => void save({ ...chat, flood_messages: Math.min(30, Math.max(2, Number(e.target.value) || 5)) })} className="mt-1 w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon" /></label>
              <label className="text-xs text-moon-dim">Окно (сек.)<input type="number" min={2} max={60} value={chat.flood_window_seconds ?? 8} onChange={(e) => void save({ ...chat, flood_window_seconds: Math.min(60, Math.max(2, Number(e.target.value) || 8)) })} className="mt-1 w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon" /></label>
            </div>

            <div className="rounded-xl border border-border bg-panel-raised/40 p-4">
              <h4 className="text-sm font-medium text-moon">Повторные нарушения</h4>
              <p className="mt-1 text-xs text-moon-dim">Текущий уровень наказания после повторных предупреждений.</p>
              <select
                value={String(chat.repeat_warn_action ?? "mute")}
                disabled={saving === String(chat.chat_id)}
                onChange={(e) => void save({ ...chat, repeat_warn_action: e.target.value as Action })}
                className="mt-3 w-full rounded-lg border border-border bg-panel px-3 py-2 text-sm text-moon outline-none sm:max-w-xs"
              >
                {ACTIONS.filter((option) => option.value !== "off").map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
              </select>
            </div>
          </div>
        </Card>
      ))}
    </div>
  );
}
