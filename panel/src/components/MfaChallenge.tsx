"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

type ChallengeResponse = {
  factor_id?: string;
  challenge_id?: string;
  already_verified?: boolean;
  error?: string;
};

export function MfaChallenge({
  nextPath = "/dashboard",
  initialError = null,
}: {
  nextPath?: string;
  initialError?: string | null;
}) {
  const router = useRouter();
  const [factorId, setFactorId] = useState("");
  const [challengeId, setChallengeId] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(initialError ? "Не удалось проверить состояние 2FA. Повторите попытку." : null);

  useEffect(() => {
    let cancelled = false;
    async function beginChallenge() {
      setLoading(true);
      try {
        const response = await fetch("/admin/api/auth/mfa", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "challenge" }),
          cache: "no-store",
        });
        const data = (await response.json().catch(() => ({}))) as ChallengeResponse;
        if (!response.ok) throw new Error(data.error ?? "Не удалось запросить код 2FA.");
        if (data.already_verified) {
          router.replace(nextPath);
          router.refresh();
          return;
        }
        if (!data.factor_id || !data.challenge_id) throw new Error("Не удалось создать проверку 2FA.");
        if (!cancelled) {
          setFactorId(data.factor_id);
          setChallengeId(data.challenge_id);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : "Не удалось запросить код 2FA.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    void beginChallenge();
    return () => { cancelled = true; };
  }, [nextPath, router]);

  async function verify() {
    if (!/^\d{6}$/.test(code) || !factorId || !challengeId) return;
    setBusy(true);
    setError(null);
    try {
      const response = await fetch("/admin/api/auth/mfa", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "verify", factor_id: factorId, challenge_id: challengeId, code }),
        cache: "no-store",
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error ?? "Неверный код 2FA.");
      router.replace(nextPath);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось проверить код 2FA.");
      setCode("");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="prisma-auth-page prisma-liquid-bg flex min-h-svh items-center justify-center px-4 py-8">
      <section className="prisma-login-card prisma-glass-surface prisma-stagger w-full max-w-[420px] rounded-xl border p-6 shadow-sm">
        <div className="mb-5 flex size-11 items-center justify-center rounded-xl bg-primary/10 text-lg" aria-hidden>⌁</div>
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">Защита аккаунта</p>
        <h1 className="mt-2 text-2xl font-semibold tracking-tight">Подтвердите вход</h1>
        <p className="mt-2 text-sm leading-6 text-muted-foreground">
          Введите 6-значный код из приложения-аутентификатора, чтобы открыть панель PRISMA.
        </p>

        {error && <div role="alert" className="prisma-glass-surface mt-4 rounded-lg border border-destructive/30 px-3 py-2 text-sm text-destructive">{error}</div>}

        <form
          className="prisma-stagger-2 mt-5 space-y-3"
          onSubmit={(event) => { event.preventDefault(); void verify(); }}
        >
          <label htmlFor="mfa-code" className="block text-sm font-medium">Код 2FA</label>
          <input
            id="mfa-code"
            autoComplete="one-time-code"
            inputMode="numeric"
            pattern="[0-9]{6}"
            maxLength={6}
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="000000"
            className="prisma-glass-control h-12 w-full rounded-lg border bg-background px-3 text-center font-mono text-xl tracking-[0.45em] outline-none focus:border-primary"
            disabled={loading || busy || !challengeId}
          />
          <button
            type="submit"
            disabled={loading || busy || code.length !== 6 || !challengeId}
            className="prisma-glass-primary prisma-glass-shimmer inline-flex h-10 w-full items-center justify-center rounded-lg border px-4 text-sm font-semibold text-primary-foreground disabled:cursor-not-allowed disabled:opacity-50"
          >
            {loading ? "Запрашиваю проверку…" : busy ? "Проверяю…" : "Подтвердить"}
          </button>
        </form>

        <form action="/admin/api/auth/logout" method="post" className="mt-3">
          <button type="submit" className="prisma-glass-control prisma-glass-hover h-10 w-full rounded-lg border px-4 text-sm text-muted-foreground transition hover:text-foreground">
            Выйти из аккаунта
          </button>
        </form>
      </section>
    </main>
  );
}
