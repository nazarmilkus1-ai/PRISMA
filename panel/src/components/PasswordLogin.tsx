"use client";

import { useState } from "react";
import { fetchJson } from "@prisma-eco/shared";

export function PasswordLogin() {
  const [telegramId, setTelegramId] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function login() {
    setError(null);
    if (!/^\d+$/.test(telegramId.trim()) || password.length < 8) return setError("Укажите Telegram ID и пароль.");
    setBusy(true);
    const { response: res, data } = await fetchJson("/admin/api/auth/password/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ telegramId: telegramId.trim(), password }) });
    setBusy(false);
    if (!res.ok) return setError(data.error === "not_an_admin" ? "У этого Telegram нет доступа к панели." : "Неверный Telegram ID или пароль.");
    window.location.assign("/admin/dashboard");
  }

  return (
    <details className="prisma-stagger-4 mt-5 text-left">
      <summary className="cursor-pointer text-center text-xs text-moon-dim hover:text-moon">Резервный вход по паролю</summary>
      <div className="mt-4 space-y-2">
        <input inputMode="numeric" value={telegramId} onChange={(e) => setTelegramId(e.target.value.replace(/\D/g, ""))} placeholder="Telegram ID" className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse" />
        <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Пароль" className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse" />
        <button onClick={login} disabled={busy} className="w-full rounded-lg border border-border px-3 py-2.5 text-sm text-moon transition-colors hover:bg-panel-raised disabled:opacity-40">{busy ? "Вход…" : "Войти"}</button>
        {error && <p className="text-xs text-danger">{error}</p>}
      </div>
    </details>
  );
}
