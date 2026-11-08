"use client";
import { useState } from "react";
import { fetchJson } from "@prisma-eco/shared";

type Step = "idle" | "waiting" | "submitting";

const ERROR_MESSAGES: Record<string, string> = {
  invalid_code: "Неверный код. Проверьте сообщение от бота.",
  code_not_ready: "Бот ещё не прислал код — откройте бота и нажмите Start.",
  not_an_admin: "Этот аккаунт не входит в список администраторов.",
  login_expired: "Время вышло. Начните вход заново.",
  auth_failed: "Не удалось создать сессию. Попробуйте ещё раз.",
  server_misconfigured: "Панель ещё не настроена — обратитесь к владельцу.",
};

export function TelegramCodeLogin() {
  const [step, setStep] = useState<Step>("idle");
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [botDeepLink, setBotDeepLink] = useState<string | null>(null);
  const [startCommand, setStartCommand] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function startLogin() {
    setError(null);
    setCopied(false);
    const { response: res, data } = await fetchJson<{ error?: string; sessionToken?: string; botDeepLink?: string }>("/admin/api/auth/telegram/start", { method: "POST" });
    if (!res.ok) {
      setError(ERROR_MESSAGES[data.error ?? ""] ?? "Не удалось начать вход. Попробуйте ещё раз.");
      return;
    }
    if (!data.sessionToken) {
      setError("Панель не вернула токен входа.");
      return;
    }
    setSessionToken(data.sessionToken);
    setBotDeepLink(data.botDeepLink ?? null);
    setStartCommand(`/start ${data.sessionToken}`);
    setCode("");
    setStep("waiting");
  }

  async function copyCommand() {
    if (!startCommand) return;
    try {
      await navigator.clipboard.writeText(startCommand);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // clipboard API unavailable (e.g. http, older browser) — the text is
      // still selectable/visible, so this is a soft failure.
    }
  }

  async function submitCode(e: React.FormEvent) {
    e.preventDefault();
    if (!sessionToken) return;
    setStep("submitting");
    setError(null);
    const res = await fetch("/admin/api/auth/telegram/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionToken, code }),
    });
    if (res.ok) {
      window.location.href = "/admin/dashboard";
      return;
    }
    const data = (await res.json().catch(() => ({}))) as { error?: string };
    setStep("waiting");
    setError(ERROR_MESSAGES[data.error ?? ""] ?? "Что-то пошло не так. Попробуйте ещё раз.");
  }

  if (step === "idle") {
    return (
      <div className="w-full prisma-stagger">
        <button
          type="button"
          onClick={startLogin}
          className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-ember/20 px-4 py-2.5 text-sm font-medium text-ember transition-colors hover:bg-ember/30"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm4.64 6.8-1.65 7.78c-.12.55-.45.68-.91.42l-2.52-1.86-1.22 1.17c-.13.13-.25.25-.51.25l.18-2.57 4.68-4.22c.2-.18-.04-.28-.31-.1l-5.78 3.64-2.49-.78c-.54-.17-.55-.54.11-.8l9.74-3.75c.45-.17.85.1.68.82z" />
          </svg>
          Войти через Telegram
        </button>
        {error && <p className="mt-3 text-xs text-danger">{error}</p>}
      </div>
    );
  }

  return (
    <div className="w-full space-y-3 text-left prisma-stagger">
      <ol className="prisma-stagger-2 list-decimal space-y-2 pl-4 text-xs text-moon-dim">
        <li>
          Откройте бота:{" "}
          <a href={botDeepLink ?? "#"} target="_blank" rel="noreferrer" className="text-ember underline">
            открыть бота в Telegram
          </a>
        </li>
        <li>
          Если бот открылся без кнопки «Start» (чат уже существовал раньше) — отправьте боту эту команду вручную:
          <div className="mt-1.5 flex items-center gap-2">
            <code className="flex-1 select-all overflow-x-auto whitespace-nowrap rounded-lg border border-border bg-panel-raised px-2.5 py-2 text-[13px] text-moon">
              {startCommand}
            </code>
            <button
              type="button"
              onClick={copyCommand}
              className="shrink-0 rounded-lg bg-ember/20 px-3 py-2 text-xs font-medium text-ember transition-colors hover:bg-ember/30"
            >
              {copied ? "Скопировано" : "Копировать"}
            </button>
          </div>
        </li>
        <li>Бот пришлёт в чат 6-значный код.</li>
        <li>Вставьте код сюда и нажмите «Войти».</li>
      </ol>
      <form onSubmit={submitCode} className="prisma-stagger-3 flex gap-2">
        <input
          type="text"
          inputMode="numeric"
          pattern="\d{6}"
          maxLength={6}
          required
          autoFocus
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
          placeholder="000000"
          className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-center text-lg tracking-[0.3em] text-moon outline-none focus:border-curse"
        />
        <button
          type="submit"
          disabled={step === "submitting" || code.length !== 6}
          className="rounded-lg bg-ember/20 px-4 py-2.5 text-sm font-medium text-ember transition-colors hover:bg-ember/30 disabled:opacity-40"
        >
          {step === "submitting" ? "…" : "Войти"}
        </button>
      </form>
      <button
        type="button"
        onClick={startLogin}
        className="text-xs text-moon-dim underline decoration-dotted underline-offset-4 transition-colors hover:text-moon"
      >
        Получить новый код
      </button>
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
}
