"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { postForm, toast } from "@/lib/optimistic";

type ToastItem = { id: number; text: string; tone: "ok" | "err" };

/**
 * Progressive enhancement for every `<form method="post" action="/api/...">` on the site.
 * The click is acknowledged instantly (CSS reacts to `data-opt="pending"`), the request goes out in the
 * background, then the page data is refreshed in place. A failure restores the form and shows a toast.
 * Opt out with `data-native` on the form. Forms with file inputs always submit natively.
 */
export function OptimisticForms() {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const waiting = useRef<Set<HTMLFormElement>>(new Set());
  const seq = useRef(0);

  const push = useCallback((text: string, tone: "ok" | "err") => {
    const id = ++seq.current;
    setToasts((items) => [...items.slice(-2), { id, text, tone }]);
    window.setTimeout(() => setToasts((items) => items.filter((t) => t.id !== id)), tone === "err" ? 5000 : 2200);
  }, []);

  useEffect(() => {
    const onToast = (event: Event) => {
      const detail = (event as CustomEvent<{ text: string; tone: "ok" | "err" }>).detail;
      if (detail?.text) push(detail.text, detail.tone);
    };
    window.addEventListener("prisma:toast", onToast);
    return () => window.removeEventListener("prisma:toast", onToast);
  }, [push]);

  useEffect(() => {
    const release = () => {
      for (const form of waiting.current) delete form.dataset.opt;
      waiting.current.clear();
    };

    const onSubmit = (event: SubmitEvent) => {
      const form = event.target;
      if (!(form instanceof HTMLFormElement) || event.defaultPrevented) return;
      if ((form.getAttribute("method") || "").toLowerCase() !== "post") return;
      const action = form.getAttribute("action") || "";
      if (!action.startsWith("/api/") || action.startsWith("/api/auth/")) return;
      if (form.hasAttribute("data-native") || form.querySelector('input[type="file"]')) return;
      if (form.dataset.opt === "pending") {
        event.preventDefault();
        return;
      }

      event.preventDefault();
      const body = new FormData(form);
      const submitter = event.submitter as HTMLButtonElement | HTMLInputElement | null;
      if (submitter?.name && !body.has(submitter.name)) body.append(submitter.name, submitter.value);

      form.dataset.opt = "pending";
      void postForm(action, body).then((result) => {
        if (!result.ok) {
          delete form.dataset.opt;
          toast(result.message || "Не удалось выполнить действие.", "err");
          return;
        }
        if (result.redirectedTo) {
          router.push(result.redirectedTo);
          waiting.current.add(form);
          window.setTimeout(release, 800);
          return;
        }
        if (!form.hasAttribute("data-opt-silent")) toast(form.getAttribute("data-opt-done") || "Готово", "ok");
        waiting.current.add(form);
        startTransition(() => router.refresh());
        // Safety net: never leave a form stuck in the pending state if the refresh is slow.
        window.setTimeout(release, 4000);
      });
    };

    document.addEventListener("submit", onSubmit, true);
    return () => document.removeEventListener("submit", onSubmit, true);
  }, [router]);

  // When the refreshed server data has arrived the form is re-rendered; drop any leftover pending flags.
  useEffect(() => {
    const id = window.setInterval(() => {
      for (const form of waiting.current) {
        if (!form.isConnected) waiting.current.delete(form);
      }
    }, 1000);
    return () => window.clearInterval(id);
  }, []);

  if (!toasts.length) return null;
  return (
    <div className="prisma-toasts" role="status" aria-live="polite">
      {toasts.map((item) => (
        <div key={item.id} className={"prisma-toast " + (item.tone === "err" ? "prisma-toast-err" : "prisma-toast-ok")}>
          {item.text}
        </div>
      ))}
    </div>
  );
}
