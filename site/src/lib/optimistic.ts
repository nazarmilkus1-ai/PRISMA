"use client";

export type PostResult = { ok: boolean; message?: string; redirectedTo?: string };

const GENERIC: Record<string, string> = {
  module_disabled: "Этот раздел сейчас отключён.",
  invalid: "Проверьте введённые данные.",
  save_failed: "Не удалось сохранить. Попробуйте ещё раз.",
  forbidden: "Недостаточно прав для этого действия.",
};

export function toast(text: string, tone: "ok" | "err" = "ok") {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent("prisma:toast", { detail: { text, tone } }));
}

function errorFrom(url: URL): string | null {
  for (const [key, value] of url.searchParams) {
    if (/(^|_)error$/i.test(key)) {
      if (/[\sЀ-ӿ]/.test(value)) return value;
      return GENERIC[value] ?? "Не удалось выполнить действие.";
    }
  }
  return null;
}

/**
 * POSTs a form to an /api route in the background. The routes answer with a 303 redirect carrying the outcome in
 * the query string, so the final URL after following it tells us whether the action worked.
 */
export async function postForm(action: string, body: FormData): Promise<PostResult> {
  try {
    const response = await fetch(action, {
      method: "POST",
      body,
      credentials: "same-origin",
      headers: { "X-Prisma-Optimistic": "1" },
    });
    const finalUrl = new URL(response.url, window.location.href);
    if (finalUrl.pathname.startsWith("/login")) {
      window.location.assign("/login");
      return { ok: false, message: "Сессия истекла. Войдите снова." };
    }
    const message = errorFrom(finalUrl);
    if (message) return { ok: false, message };
    if (!response.ok) return { ok: false, message: "Не удалось выполнить действие." };
    const moved = finalUrl.pathname !== window.location.pathname;
    return { ok: true, redirectedTo: moved ? finalUrl.pathname + finalUrl.search : undefined };
  } catch {
    return { ok: false, message: "Нет связи. Проверьте интернет и повторите." };
  }
}
