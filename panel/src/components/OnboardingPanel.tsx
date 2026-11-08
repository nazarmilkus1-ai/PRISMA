"use client";

import { formatDateTime } from "@prisma-eco/shared";

import { useMemo, useState } from "react";
import { Avatar, Badge, Card, SearchBar } from "@/components/ui";
import { SimplePagination } from "@prisma-eco/ui";

type OnboardingUser = {
  id: string;
  telegram_id: number;
  telegram_username: string | null;
  first_name: string | null;
  full_name: string | null;
  community_first_seen_at: string | null;
  community_last_seen_at: string | null;
  bot_started_at: string | null;
  created_at: string;
};

type Filter = "ALL" | "NOT_STARTED" | "STARTED" | "ACTIVE";

const PAGE_SIZE = 15;

function displayName(user: OnboardingUser) {
  return user.telegram_username
    ? `@${user.telegram_username}`
    : user.full_name || user.first_name || `Telegram ${user.telegram_id}`;
}



function active(user: OnboardingUser) {
  return !!user.community_last_seen_at
    && Date.now() - new Date(user.community_last_seen_at).getTime() <= 7 * 24 * 60 * 60_000;
}

export function OnboardingPanel({
  users,
  botUsername,
}: {
  users: OnboardingUser[];
  botUsername: string;
}) {
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<Filter>("ALL");
  const [page, setPage] = useState(1);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [broadcastTitle, setBroadcastTitle] = useState("PRISMA — заявка на вступление");
  const [broadcastBody, setBroadcastBody] = useState("Вы уже в сообществе PRISMA, но ещё не подали заявку. Откройте бота PRISMA, заполните анкету и получите доступ к Minecraft-серверу.");
  const [broadcastBusy, setBroadcastBusy] = useState(false);
  const [broadcastResult, setBroadcastResult] = useState<string | null>(null);
  const [broadcastError, setBroadcastError] = useState<string | null>(null);

  const botUrl = `https://t.me/${botUsername.replace(/^@/, "")}?start=onboarding`;

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return users.filter((user) => {
      if (filter === "NOT_STARTED" && user.bot_started_at) return false;
      if (filter === "STARTED" && !user.bot_started_at) return false;
      if (filter === "ACTIVE" && !active(user)) return false;
      if (!q) return true;
      return [
        user.telegram_username,
        user.full_name,
        user.first_name,
        user.telegram_id,
      ].filter(Boolean).some((value) => String(value).toLowerCase().includes(q));
    });
  }, [filter, search, users]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visible = filtered.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);
  const notStarted = users.filter((user) => !user.bot_started_at).length;
  const started = users.length - notStarted;
  const activeCount = users.filter(active).length;

  async function copyLink(id: string) {
    try {
      await navigator.clipboard.writeText(botUrl);
      setCopiedId(id);
      window.setTimeout(() => setCopiedId(null), 1200);
    } catch {
      setCopiedId(null);
    }
  }

  function reset() {
    setSearch("");
    setFilter("ALL");
    setPage(1);
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Card className="p-4"><p className="text-xs text-moon-dim">Без анкеты</p><p className="mt-1 font-display text-2xl text-moon">{users.length}</p></Card>
        <Card className="p-4"><p className="text-xs text-moon-dim">Бот ещё не открывали</p><p className="mt-1 font-display text-2xl text-moon">{notStarted}</p></Card>
        <Card className="p-4"><p className="text-xs text-moon-dim">Бот открывали</p><p className="mt-1 font-display text-2xl text-moon">{started}</p></Card>
        <Card className="p-4"><p className="text-xs text-moon-dim">Активны за 7 дней</p><p className="mt-1 font-display text-2xl text-moon">{activeCount}</p></Card>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b border-border p-4">
          <div className="flex flex-col gap-1">
            <h2 className="font-medium text-moon">Рассылка без анкеты</h2>
            <p className="text-xs text-moon-dim">
              Сообщение получат только пользователи без заявки, которые уже открывали бота. Тех, кто никогда не запускал бота, Telegram не позволяет автоматически уведомить в личке.
            </p>
          </div>
        </div>
        <div className="grid gap-3 p-4">
          <input
            value={broadcastTitle}
            onChange={(e) => setBroadcastTitle(e.target.value)}
            maxLength={200}
            placeholder="Заголовок"
            className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse"
          />
          <textarea
            value={broadcastBody}
            onChange={(e) => setBroadcastBody(e.target.value)}
            maxLength={4000}
            rows={4}
            placeholder="Текст рассылки"
            className="w-full resize-y rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse"
          />
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-xs text-moon-dim">
              Получателей сейчас: <span className="font-medium text-moon">{started}</span>
            </p>
            <button
              onClick={async () => {
                setBroadcastBusy(true);
                setBroadcastError(null);
                setBroadcastResult(null);
                try {
                  const res = await fetch("/admin/api/onboarding", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ title: broadcastTitle, body: broadcastBody }),
                  });
                  const data = await res.json().catch(() => ({}));
                  if (!res.ok) throw new Error(data.error?.message ?? data.error ?? "Не удалось запустить рассылку.");
                  const result = data.result ?? {};
                  setBroadcastResult(`Отправлено в очередь: ${Number(result.recipients ?? 0)}. Без возможности личной доставки: ${Number(result.unreachable_without_bot ?? 0)}.`);
                } catch (e) {
                  setBroadcastError(e instanceof Error ? e.message : "Не удалось запустить рассылку.");
                } finally {
                  setBroadcastBusy(false);
                }
              }}
              disabled={broadcastBusy || !broadcastTitle.trim() || !broadcastBody.trim()}
              className="rounded-lg bg-ember/20 px-4 py-2.5 text-sm font-medium text-ember hover:bg-ember/30 disabled:cursor-not-allowed disabled:opacity-40"
            >
              {broadcastBusy ? "Запускаю…" : "Запустить рассылку"}
            </button>
          </div>
          {broadcastResult && <p className="rounded-lg border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{broadcastResult}</p>}
          {broadcastError && <p className="rounded-lg border border-danger/30 bg-danger/10 px-3 py-2 text-xs text-danger">{broadcastError}</p>}
        </div>
      </Card>
      <Card className="overflow-hidden">
        <div className="space-y-3 border-b border-border p-4">
          <div className="flex flex-col gap-2 sm:flex-row">
            <SearchBar
              value={search}
              onChange={(value) => { setSearch(value); setPage(1); }}
              placeholder="@username, имя или Telegram ID…"
              className="flex-1"
            />
            <a
              href={botUrl}
              target="_blank"
              rel="noreferrer"
              className="rounded-lg bg-ember/15 px-4 py-2.5 text-center text-sm text-ember hover:bg-ember/25"
            >
              Открыть бота
            </a>
          </div>
          <div className="flex flex-wrap gap-1">
            {([
              ["ALL", "Все"],
              ["NOT_STARTED", "Бот не открывали"],
              ["STARTED", "Уже открывали"],
              ["ACTIVE", "Активны 7 дней"],
            ] as [Filter, string][]).map(([key, label]) => (
              <button
                key={key}
                onClick={() => { setFilter(key); setPage(1); }}
                className={`rounded-lg px-3 py-1.5 text-xs ${filter === key ? "bg-panel-raised text-moon" : "text-moon-dim hover:text-moon"}`}
              >
                {label}
              </button>
            ))}
            {(search || filter !== "ALL") && (
              <button onClick={reset} className="ml-auto px-2 text-xs text-ember hover:underline">
                Сбросить
              </button>
            )}
          </div>
          <p className="text-xs text-moon-dim">
            Список состоит только из людей, которых бот уже видел в группе. Тех, кто ещё ни разу не взаимодействовал с ботом в группе, Telegram не позволяет определить автоматически.
          </p>
        </div>

        <div className="divide-y divide-border">
          {visible.map((user) => {
            const botOpened = !!user.bot_started_at;
            return (
              <div key={user.id} className="flex flex-col gap-3 p-4 md:flex-row md:items-center">
                <Avatar name={displayName(user)} size="md" />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="truncate text-sm text-moon">{displayName(user)}</p>
                    {active(user) && <span className="h-1.5 w-1.5 rounded-full bg-success" title="Активен за 7 дней" />}
                  </div>
                  <p className="mt-0.5 text-xs text-moon-dim">
                    В группе с {user.community_first_seen_at ? formatDateTime(user.community_first_seen_at) : "—"} · последняя активность {user.community_last_seen_at ? formatDateTime(user.community_last_seen_at) : "—"}
                  </p>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <Badge tone={botOpened ? "success" : "warn"}>
                    {botOpened ? "Бот открыт" : "Бот не открыт"}
                  </Badge>
                  <a
                    href={botUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="rounded-lg border border-border px-3 py-1.5 text-xs text-moon-dim hover:text-moon"
                  >
                    Ссылка
                  </a>
                  <button
                    onClick={() => void copyLink(user.id)}
                    className="rounded-lg border border-border px-3 py-1.5 text-xs text-moon-dim hover:text-moon"
                  >
                    {copiedId === user.id ? "Скопировано" : "Копировать"}
                  </button>
                </div>
              </div>
            );
          })}
          {!visible.length && (
            <div className="p-10 text-center text-sm text-moon-dim">Нет пользователей, соответствующих фильтрам.</div>
          )}
        </div>

        {totalPages > 1 && (
          <div className="border-t border-border p-3">
            <SimplePagination page={currentPage} totalPages={totalPages} onChange={setPage} />
          </div>
        )}
      </Card>
    </div>
  );
}
