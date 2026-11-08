"use client";

import { useState } from "react";
import { fetchJson } from "@prisma-eco/shared";
import { usePrismaProcessNotification } from "@/components/PrismaProcessNotification";

type Step = "idle" | "waiting" | "submitting";

const errors: Record<string, string> = {
  invalid_code: "Неверный код.",
  code_not_ready: "Бот ещё не прислал код. Откройте бота и нажмите Start.",
  login_expired: "Код устарел. Начните вход заново.",
  not_registered: "Сначала откройте бота PRISMA и пройдите регистрацию.",
  auth_failed: "Не удалось выполнить вход. Попробуйте ещё раз.",
  rate_limited: "Слишком много попыток. Попробуйте позже.",
  server_misconfigured: "Сайт сейчас настроен неправильно. Сообщите администратору PRISMA.",
};

export function LoginForm({ next = "/app" }: { next?: string }) {
  const [step, setStep] = useState<Step>("idle");
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [deepLink, setDeepLink] = useState<string | null>(null);
  const [command, setCommand] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { start: startProcess, dismiss: dismissProcess } =
    usePrismaProcessNotification();

  const redirectTarget = typeof next === "string" && next.startsWith("/") && !next.startsWith("//") ? next : "/app";

  async function start() {
    setError(null);
    startProcess(
      [
        { text: "Создаём защищённую сессию" },
        { text: "Готовим вход через Telegram" },
      ],
      900,
    );
    setCopied(false);
    const { response, data } = await fetchJson("/api/auth/telegram/start", { method: "POST" });
    const payload = data as { error?: string; sessionToken?: string; botDeepLink?: string };
    if (!response.ok) {
      dismissProcess();
      setError(errors[payload.error ?? ""] || "Не удалось начать вход.");
      return;
    }
    if (!payload.sessionToken) {
      dismissProcess();
      setError("Сайт не вернул токен входа.");
      return;
    }
    setSessionToken(payload.sessionToken);
    setDeepLink(payload.botDeepLink ?? null);
    setCommand("/start " + payload.sessionToken);
    setCode("");
    setStep("waiting");
  }

  async function copy() {
    if (!command) return;
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {}
  }

  async function verify(event: React.FormEvent) {
    event.preventDefault();
    if (!sessionToken || code.length !== 6) return;
    startProcess(
      [
        { text: "Проверяем одноразовый код" },
        { text: "Завершаем вход в PRISMA" },
      ],
      800,
    );
    setStep("submitting");
    setError(null);
    const { response, data } = await fetchJson("/api/auth/telegram/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionToken, code }),
    });
    if (response.ok) {
      window.location.assign(redirectTarget);
      return;
    }
    dismissProcess();
    setStep("waiting");
    const payload = data as { error?: string };
    setError(errors[payload.error ?? ""] || "Не удалось выполнить вход.");
  }

  if (step === "idle") {
    return (
      <div className="space-y-4 prisma-stagger">
        <button onClick={start} className="w-full rounded-xl bg-[var(--primary)] px-4 py-3 text-sm font-semibold text-[var(--primary-foreground)] shadow-sm hover:brightness-95">
          Войти через Telegram
        </button>
        <p className="text-center text-xs text-[var(--muted-foreground)]">
          Один аккаунт PRISMA для сайта и Telegram.
        </p>
        {error && <p className="text-sm text-[var(--danger)]">{error}</p>}
      </div>
    );
  }

  return (
    <div className="space-y-5 prisma-stagger">
      <div className="prisma-stagger-2 prisma-glass-surface rounded-xl border p-4">
        <p className="text-sm font-semibold">Вход через Telegram</p>
        <ol className="mt-3 space-y-2 pl-5 text-sm text-[var(--muted-foreground)]">
          <li>Откройте бота и нажмите Start.</li>
          <li>Если кнопка Start не появилась, отправьте команду ниже.</li>
          <li>Бот пришлёт одноразовый 6-значный код.</li>
          <li>Введите его здесь.</li>
        </ol>
        {deepLink && (
          <a href={deepLink} target="_blank" rel="noreferrer" className="prisma-glass-control prisma-glass-hover mt-4 inline-flex rounded-lg border px-3 py-2 text-sm font-medium">
            Открыть бота
          </a>
        )}
        {command && (
          <div className="mt-3 flex gap-2">
            <code className="prisma-glass-surface min-w-0 flex-1 overflow-hidden rounded-lg border px-3 py-2 text-xs">{command}</code>
            <button onClick={copy} className="prisma-glass-control prisma-glass-hover shrink-0 rounded-lg border px-3 py-2 text-xs font-medium">{copied ? "Скопировано" : "Копировать"}</button>
          </div>
        )}
      </div>

      <form onSubmit={verify} className="prisma-stagger-3 space-y-3">
        <input
          required
          autoFocus
          inputMode="numeric"
          pattern="\d{6}"
          maxLength={6}
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
          placeholder="000000"
          className="prisma-glass-surface w-full rounded-xl border px-4 py-3 text-center text-xl tracking-[0.35em] outline-none focus:ring-2 focus:ring-[var(--primary)]"
        />
        <button disabled={step === "submitting" || code.length !== 6} className="prisma-glass-control prisma-glass-hover w-full rounded-xl border px-4 py-3 text-sm font-semibold disabled:opacity-40">
          {step === "submitting" ? "Проверяем…" : "Войти"}
        </button>
      </form>

      {error && <p className="text-sm text-[var(--danger)]">{error}</p>}
      <button onClick={start} className="text-xs text-[var(--muted-foreground)] underline underline-offset-4">Получить новый код</button>
    </div>
  );
}
