"use client";

import { useEffect, useState } from "react";
import { fetchJson } from "@prisma-eco/shared";
import { Card } from "@/components/ui";

type SecurityData = {
  profile: {
    id: string;
    telegram_id: number;
    telegram_username: string | null;
    first_name: string | null;
    last_name: string | null;
    full_name: string | null;
    phone_number: string | null;
    status: string;
    rating: number;
    activity_score: number;
    last_seen_at: string | null;
    created_at: string;
    minecraft_nickname: string | null;
    platform: string | null;
  } | null;
  role: string | null;
  permissions: string[];
  auth: {
    email: string | null;
    telegram_id: number | null;
    aal: string;
    next_aal: string | null;
    factors: { id: string; type: string; name: string; status: string }[];
  };
  login_history: { id: string; method: string; success: boolean; ip_hash: string | null; user_agent: string | null; created_at: string }[];
};

type SecurityResponse = SecurityData & { error?: string };

function formatDate(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ru-RU", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

export function PasswordSettings() {
  const [security, setSecurity] = useState<SecurityData | null>(null);
  const [password, setPassword] = useState("");
  const [repeat, setRepeat] = useState("");
  const [busy, setBusy] = useState(false);
  const [sessionBusy, setSessionBusy] = useState(false);
  const [mfaBusy, setMfaBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [mfaSetup, setMfaSetup] = useState<{ factor_id: string; challenge_id: string; qr_code: string | null; secret: string | null } | null>(null);
  const [mfaCode, setMfaCode] = useState("");

  async function loadSecurity() {
    try {
      const { response: res, data } = await fetchJson<SecurityResponse>("/admin/api/auth/security", { cache: "no-store" });
      if (!res.ok) throw new Error(data.error ?? "Не удалось загрузить данные безопасности.");
      setSecurity(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось загрузить данные безопасности.");
    }
  }

  useEffect(() => { void loadSecurity(); }, []);

  async function savePassword() {
    setError(null); setMessage(null);
    if (password.length < 8) return setError("Пароль должен содержать не менее 8 символов.");
    if (password !== repeat) return setError("Новые пароли не совпадают.");
    setBusy(true);
    try {
      const res = await fetch("/admin/api/auth/password/set", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось изменить пароль.");
      setPassword(""); setRepeat("");
      setMessage("Пароль обновлён. Supabase Auth хранит его как хеш — значение пароля не попадает в таблицы PRISMA.");
      await loadSecurity();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось изменить пароль.");
    } finally {
      setBusy(false);
    }
  }

  async function revokeOtherSessions() {
    setError(null); setMessage(null); setSessionBusy(true);
    try {
      const { response: res, data } = await fetchJson<SecurityResponse>("/admin/api/auth/security", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "revoke_other_sessions" }) });
      if (!res.ok) throw new Error(data.error ?? "Не удалось завершить другие сессии.");
      setMessage("Все остальные активные сессии завершены.");
      await loadSecurity();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось завершить другие сессии.");
    } finally {
      setSessionBusy(false);
    }
  }

  async function startMfa() {
    setError(null); setMessage(null); setMfaBusy(true);
    try {
      const res = await fetch("/admin/api/auth/mfa", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "enroll" }) });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось запустити налаштування 2FA.");
      setMfaSetup(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось запустити налаштування 2FA.");
    } finally {
      setMfaBusy(false);
    }
  }

  async function verifyMfa() {
    if (!mfaSetup) return;
    setError(null); setMessage(null); setMfaBusy(true);
    try {
      const res = await fetch("/admin/api/auth/mfa", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "verify", factor_id: mfaSetup.factor_id, challenge_id: mfaSetup.challenge_id, code: mfaCode }) });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Неверный код 2FA.");
      setMfaSetup(null); setMfaCode(""); setMessage("2FA включена. Supabase Auth перевёл текущую сессию на AAL2.");
      await loadSecurity();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось проверить 2FA.");
    } finally {
      setMfaBusy(false);
    }
  }

  async function disableMfa(factorId: string) {
    setError(null); setMessage(null); setMfaBusy(true);
    try {
      const res = await fetch("/admin/api/auth/mfa", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "unenroll", factor_id: factorId }) });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "Не удалось вимкнути 2FA.");
      setMessage("Фактор 2FA удалён.");
      await loadSecurity();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось вимкнути 2FA.");
    } finally {
      setMfaBusy(false);
    }
  }

  const profile = security?.profile;
  const displayName = profile?.full_name || [profile?.first_name, profile?.last_name].filter(Boolean).join(" ") || security?.auth.email || "Администратор";
  const username = profile?.telegram_username ? `@${profile.telegram_username.replace(/^@/, "")}` : "username не указан";

  return (
    <div className="space-y-4">
      <Card className="p-5">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs uppercase tracking-wider text-moon-dim">Профиль администратора</p>
            <h2 className="mt-1 text-xl font-semibold text-moon">{displayName}</h2>
            <p className="mt-1 text-sm text-moon-dim">{username}</p>
          </div>
          <div className="rounded-xl border border-border bg-panel-raised px-4 py-3 text-sm">
            <p className="text-xs text-moon-dim">Роль</p>
            <p className="mt-1 font-medium text-moon">{security?.role ?? "—"}</p>
          </div>
        </div>
        <div className="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-xl border border-border bg-panel-raised/50 p-3"><p className="text-xs text-moon-dim">Telegram ID</p><p className="mt-1 font-mono text-sm text-moon">{profile?.telegram_id ?? security?.auth.telegram_id ?? "—"}</p></div>
          <div className="rounded-xl border border-border bg-panel-raised/50 p-3"><p className="text-xs text-moon-dim">Minecraft</p><p className="mt-1 text-sm text-moon">{profile?.minecraft_nickname ?? "Не привязано"}</p></div>
          <div className="rounded-xl border border-border bg-panel-raised/50 p-3"><p className="text-xs text-moon-dim">Рейтинг</p><p className="mt-1 text-sm text-moon">{profile?.rating ?? "—"}</p></div>
          <div className="rounded-xl border border-border bg-panel-raised/50 p-3"><p className="text-xs text-moon-dim">Последняя активность</p><p className="mt-1 text-sm text-moon">{formatDate(profile?.last_seen_at ?? null)}</p></div>
        </div>
      </Card>

      <Card className="p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="font-medium text-moon">Безопасность</h2>
            <p className="mt-1 text-sm text-moon-dim">Пароль, двухфакторная аутентификация та активные сессии.</p>
          </div>
          <div className={`rounded-full px-3 py-1 text-xs ${security?.auth.aal === "aal2" ? "bg-success/10 text-success" : "bg-ember/10 text-ember"}`}>
            {security?.auth.aal === "aal2" ? "AAL2 · 2FA активна" : "AAL1 · 2FA не пройдена"}
          </div>
        </div>

        <div className="mt-5 border-t border-border pt-5">
          <h3 className="text-sm font-medium text-moon">Изменить пароль</h3>
          <p className="mt-1 text-xs text-moon-dim">Минимум 8 символов. Пароль обрабатывает Supabase Auth.</p>
          <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
            <input type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Новый пароль" className="rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse" />
            <input type="password" autoComplete="new-password" value={repeat} onChange={(e) => setRepeat(e.target.value)} placeholder="Повторите пароль" className="rounded-lg border border-border bg-panel-raised px-3 py-2.5 text-sm text-moon outline-none focus:border-curse" />
          </div>
          <button onClick={savePassword} disabled={busy} className="mt-3 rounded-lg bg-ember/15 px-4 py-2.5 text-sm font-medium text-ember hover:bg-ember/25 disabled:opacity-40">{busy ? "Сохраняю…" : "Изменить пароль"}</button>
        </div>

        <div className="mt-5 border-t border-border pt-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 className="text-sm font-medium text-moon">Двухфакторная аутентификация</h3>
              <p className="mt-1 text-xs text-moon-dim">TOTP через приложение-аутентификатор. Состояние фактора: {security?.auth.factors.length ? security.auth.factors.map((factor) => `${factor.name} (${factor.status})`).join(", ") : "не настроено"}.</p>
            </div>
            {!security?.auth.factors.some((factor) => factor.status === "verified") && <button onClick={() => void startMfa()} disabled={mfaBusy} className="rounded-lg border border-border px-4 py-2 text-sm text-moon hover:bg-panel-raised disabled:opacity-40">Включить 2FA</button>}
          </div>
          {security?.auth.factors.filter((factor) => factor.status === "verified").map((factor) => (
            <div key={factor.id} className="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border bg-panel-raised/50 px-3 py-2">
              <span className="text-sm text-moon">{factor.name} · {factor.type}</span>
              <button onClick={() => void disableMfa(factor.id)} disabled={mfaBusy} className="text-xs text-danger hover:underline disabled:opacity-40">Вимкнути</button>
            </div>
          ))}
          {mfaSetup && (
            <div className="mt-4 rounded-xl border border-border bg-panel-raised p-4">
              <p className="text-sm font-medium text-moon">Подключение Authenticator</p>
              {mfaSetup.qr_code && <img src={mfaSetup.qr_code} alt="QR-код для 2FA" className="mt-3 h-48 w-48 rounded-lg bg-white p-2" />}
              {mfaSetup.secret && <p className="mt-3 break-all font-mono text-xs text-moon-dim">Секрет: {mfaSetup.secret}</p>}
              <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                <input value={mfaCode} onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, "").slice(0, 6))} inputMode="numeric" placeholder="6-значный код" className="rounded-lg border border-border bg-panel px-3 py-2 text-sm text-moon" />
                <button onClick={() => void verifyMfa()} disabled={mfaBusy || mfaCode.length !== 6} className="rounded-lg bg-ember/15 px-4 py-2 text-sm text-ember disabled:opacity-40">Подтвердить 2FA</button>
              </div>
            </div>
          )}
        </div>

        <div className="mt-5 border-t border-border pt-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div><h3 className="text-sm font-medium text-moon">Активные сессии</h3><p className="mt-1 text-xs text-moon-dim">Кнопка завершает все остальные сессии, текущую оставляет.</p></div>
            <button onClick={() => void revokeOtherSessions()} disabled={sessionBusy} className="rounded-lg border border-border px-4 py-2 text-sm text-moon hover:bg-panel-raised disabled:opacity-40">{sessionBusy ? "Завершаю…" : "Выйти с других устройств"}</button>
          </div>
        </div>
      </Card>

      <Card className="p-5">
        <div className="flex items-center justify-between gap-3"><h2 className="font-medium text-moon">История входов</h2><span className="text-xs text-moon-dim">Последние {security?.login_history.length ?? 0}</span></div>
        <div className="mt-3 space-y-2">
          {(security?.login_history ?? []).map((entry) => (
            <div key={entry.id} className="grid grid-cols-1 gap-1 rounded-lg border border-border bg-panel-raised/40 p-3 sm:grid-cols-[1fr_auto]">
              <div><p className="text-sm text-moon">{entry.method} · {entry.success ? "успешно" : "ошибка"}</p><p className="mt-1 text-xs text-moon-dim">{entry.user_agent || "Браузер не определён"}{entry.ip_hash ? ` · IP fingerprint ${entry.ip_hash}` : ""}</p></div>
              <p className="text-xs text-moon-dim sm:text-right">{formatDate(entry.created_at)}</p>
            </div>
          ))}
          {!security?.login_history.length && <p className="py-4 text-sm text-moon-dim">История входов поки порожня.</p>}
        </div>
      </Card>

      {error && <div className="rounded-lg border border-danger/30 bg-danger/10 px-3 py-2 text-sm text-danger">{error}</div>}
      {message && <div className="rounded-lg border border-success/30 bg-success/10 px-3 py-2 text-sm text-success">{message}</div>}
    </div>
  );
}
