import "server-only";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

type Json = Record<string, unknown>;

const RENDER_API = "https://api.render.com/v1";
const DOWN_MINUTES_BEFORE_RESTART = Number(process.env.GUARDIAN_DOWN_MINUTES ?? 10);
const RESTART_COOLDOWN_MIN = Number(process.env.GUARDIAN_RESTART_COOLDOWN_MIN ?? 30);
const RESTART_DAILY_CAP = Number(process.env.GUARDIAN_RESTART_DAILY_CAP ?? 3);
const REALERT_MIN = 60;

export function renderConfigured() {
  return Boolean(process.env.RENDER_API_KEY && process.env.RENDER_SERVICE_ID);
}

async function renderFetch(path: string, init: RequestInit = {}) {
  return fetch(`${RENDER_API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${process.env.RENDER_API_KEY}`,
      Accept: "application/json",
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(20_000),
  });
}

export async function sendTelegram(text: string) {
  const token = process.env.BOT_TOKEN;
  const chat = process.env.GUARDIAN_ALERT_CHAT_ID || process.env.ADMIN_GROUP_ID || process.env.OWNER_TG_ID;
  if (!token || !chat) return false;
  const thread = process.env.GUARDIAN_ALERT_THREAD_ID;
  const body: Json = { chat_id: chat, text: text.slice(0, 3500), disable_web_page_preview: true };
  if (thread) body.message_thread_id = Number(thread);
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function checkBot(): Promise<{ ok: boolean; detail: string }> {
  const url = process.env.BOT_HEALTH_URL || "https://prisma-a8qt.onrender.com/health";
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(30_000), cache: "no-store" });
    return { ok: res.ok, detail: `HTTP ${res.status}` };
  } catch (e) {
    return { ok: false, detail: e instanceof Error ? e.name : "error" };
  }
}

async function latestRenderDeploy(): Promise<{ id: string; status: string } | null> {
  if (!renderConfigured()) return null;
  try {
    const res = await renderFetch(`/services/${process.env.RENDER_SERVICE_ID}/deploys?limit=1`);
    if (!res.ok) return null;
    const data = (await res.json()) as Array<{ deploy?: { id: string; status: string } }>;
    const d = data?.[0]?.deploy;
    return d ? { id: d.id, status: d.status } : null;
  } catch {
    return null;
  }
}

export async function runTick() {
  const db = createSupabaseAdminClient();
  const report: Json = {};
  const now = Date.now();

  const rpc = async (fn: string, args: Json) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) throw new Error(`${fn}: ${error.message}`);
    return data;
  };
  const log = (kind: string, severity: string, summary: string, details: Json = {}) =>
    rpc("guardian_log_event", { p_kind: kind, p_severity: severity, p_summary: summary, p_details: details }).catch(() => null);

  // 1. Supabase reachability (if this fails nothing else can be recorded).
  let state: Json;
  try {
    state = ((await rpc("guardian_state_get", { p_key: "bot" })) as Json) ?? {};
  } catch (e) {
    await sendTelegram("🛡 Охранник: Supabase недоступна, проверка не выполнена.");
    return { ok: false, error: e instanceof Error ? e.message : "supabase" };
  }

  // 2. Bot health.
  const bot = await checkBot();
  report.bot = bot;
  const downSince = typeof state.down_since === "number" ? state.down_since : null;
  const lastAlert = typeof state.last_alert === "number" ? state.last_alert : 0;
  const next: Json = { ...state };

  if (bot.ok) {
    if (downSince) {
      const mins = Math.round((now - downSince) / 60000);
      await log("bot_up", "info", `Бот снова отвечает (простой ~${mins} мин)`);
      await sendTelegram(`🛡 Бот снова отвечает. Простой был ~${mins} мин.`);
    }
    next.down_since = null;
    next.last_alert = 0;
  } else {
    const since = downSince ?? now;
    const downMin = Math.round((now - since) / 60000);
    next.down_since = since;
    if (!downSince) await log("bot_down", "error", `Бот не отвечает: ${bot.detail}`);

    // Safe auto action: restart Render after N minutes down, with cooldown + daily cap.
    if (downMin >= DOWN_MINUTES_BEFORE_RESTART && renderConfigured()) {
      const allowed = await rpc("guardian_auto_action_gate", {
        p_action: "render_restart",
        p_cooldown_min: RESTART_COOLDOWN_MIN,
        p_daily_cap: RESTART_DAILY_CAP,
      }).catch(() => false);
      if (allowed) {
        const res = await renderFetch(`/services/${process.env.RENDER_SERVICE_ID}/restart`, { method: "POST" }).catch(() => null);
        const ok = Boolean(res?.ok);
        await log("render_restart", ok ? "warn" : "error", ok ? "Авторестарт Render выполнен" : `Авторестарт не удался (${res?.status ?? "net"})`);
        await sendTelegram(
          ok
            ? `🛡 Бот не отвечал ${downMin} мин. Перезапустил сервис на Render (лимит ${RESTART_DAILY_CAP}/сутки).`
            : `🛡 Бот не отвечает ${downMin} мин, авторестарт НЕ удался. Нужна ручная проверка.`,
        );
        report.restart = ok;
        next.last_alert = now;
      } else {
        report.restart = "blocked_by_gate";
      }
    }

    if (now - lastAlert > REALERT_MIN * 60000 && !report.restart) {
      await sendTelegram(
        `🛡 Бот не отвечает уже ${downMin} мин (${bot.detail}).` +
          (renderConfigured() ? " Авторестарт ограничен кулдауном/лимитом." : " Токен Render не задан — автодействия выключены."),
      );
      next.last_alert = now;
    }
  }

  // 3. Render deploy status (read-only).
  const deploy = await latestRenderDeploy();
  if (deploy) {
    report.deploy = deploy;
    const bad = ["build_failed", "update_failed", "pre_deploy_failed"].includes(deploy.status);
    if (bad && next.last_bad_deploy !== deploy.id) {
      next.last_bad_deploy = deploy.id;
      await log("deploy_failed", "error", `Деплой Render ${deploy.id}: ${deploy.status}`);
      await sendTelegram(`🛡 Деплой Render упал: ${deploy.status} (${deploy.id}). Проверь логи; откат предложить в панели /admin/dashboard/guardian.`);
      await rpc("guardian_proposal_create", {
        p_source: "guardian",
        p_kind: "render_redeploy",
        p_title: `Перезапустить деплой Render после ${deploy.status}`,
        p_body: "Последний деплой завершился ошибкой. Подтверди, чтобы запустить новый деплой текущей ветки.",
        p_payload: { failed_deploy: deploy.id },
      }).catch(() => null);
    }
  }

  await rpc("guardian_state_set", { p_key: "bot", p_value: next }).catch(() => null);
  await rpc("guardian_state_set", { p_key: "last_tick", p_value: { at: new Date(now).toISOString(), bot_ok: bot.ok } }).catch(() => null);
  return { ok: true, ...report };
}

// Execute an approved proposal. Only Render actions are wired; everything is behind a human click.
export async function executeProposal(id: string): Promise<{ ok: boolean; result: string }> {
  const db = createSupabaseAdminClient();
  const { data } = await db.rpc("guardian_proposal_take", { p_id: id });
  if (!data) return { ok: false, result: "Предложение не найдено или уже выполняется." };
  const p = data as { kind: string; payload?: { deploy_id?: string } };

  let ok = false;
  let result = "";
  try {
    if (p.kind === "note") {
      ok = true;
      result = "Принято к сведению.";
    } else if (p.kind === "render_redeploy" || p.kind === "render_rollback") {
      if (!renderConfigured()) {
        result = "RENDER_API_KEY / RENDER_SERVICE_ID не заданы в Vercel.";
      } else if (p.kind === "render_redeploy") {
        const res = await renderFetch(`/services/${process.env.RENDER_SERVICE_ID}/deploys`, { method: "POST", body: "{}" });
        ok = res.ok;
        result = ok ? "Деплой запущен." : `Render ответил ${res.status}`;
      } else {
        const deployId = p.payload?.deploy_id;
        if (!deployId) result = "Не указан deploy_id для отката.";
        else {
          const res = await renderFetch(`/services/${process.env.RENDER_SERVICE_ID}/rollback`, {
            method: "POST",
            body: JSON.stringify({ deployId }),
          });
          ok = res.ok;
          result = ok ? "Откат запущен." : `Render ответил ${res.status}`;
        }
      }
    } else {
      result = `Тип ${p.kind} пока не поддерживается автоматически.`;
    }
  } catch (e) {
    result = e instanceof Error ? e.message : "ошибка";
  }
  await db.rpc("guardian_proposal_finish", { p_id: id, p_ok: ok, p_result: result });
  return { ok, result };
}
