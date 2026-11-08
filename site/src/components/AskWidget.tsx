"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";

type Reply = { answer: string; links: { href: string; label: string }[] };

/** Floating "ask" helper for guests: code answers first, the model for the rest. */
export function AskWidget() {
  const [open, setOpen] = useState(false);
  const [question, setQuestion] = useState("");
  const [reply, setReply] = useState<Reply | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const value = question.trim();
    if (value.length < 2 || busy) return;
    setBusy(true);
    setReply(null);
    try {
      const response = await fetch("/api/ai/ask", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question: value }),
      });
      const data = await response.json();
      setReply({ answer: String(data.answer ?? "Не получилось ответить."), links: Array.isArray(data.links) ? data.links : [] });
    } catch {
      setReply({ answer: "Нет связи. Попробуйте ещё раз.", links: [] });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed bottom-4 right-4 z-50 flex flex-col items-end gap-2">
      {open ? (
        <section
          aria-label="Помощник PRISMA"
          className="prisma-glass-surface w-[min(92vw,22rem)] rounded-2xl border border-white/10 p-4"
        >
          <div className="flex items-center justify-between gap-2">
            <h2 className="text-sm font-bold">Спросить PRISMA</h2>
            <button type="button" onClick={() => setOpen(false)} aria-label="Закрыть" className="text-lg leading-none text-muted-foreground">
              ×
            </button>
          </div>
          <form onSubmit={submit} className="mt-3 flex gap-2">
            <input
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              maxLength={500}
              placeholder="Как попасть на сервер?"
              aria-label="Ваш вопрос"
              className="min-w-0 flex-1 rounded-lg border border-white/10 bg-black/40 px-3 py-2 text-sm outline-none focus:border-white/40"
            />
            <button type="submit" disabled={busy} className="ox-btn ox-btn-sm ox-btn-solid">
              {busy ? "…" : "OK"}
            </button>
          </form>
          {reply ? (
            <div className="mt-3 text-sm leading-6" role="status">
              <p className="whitespace-pre-line">{reply.answer}</p>
              {reply.links.length ? (
                <div className="mt-2 flex flex-wrap gap-2">
                  {reply.links.map((link) => (
                    <Link key={link.href} href={link.href} className="ox-btn ox-btn-sm" onClick={() => setOpen(false)}>
                      {link.label}
                    </Link>
                  ))}
                </div>
              ) : null}
            </div>
          ) : (
            <p className="mt-3 text-xs text-muted-foreground">Подскажу, где что находится и как подать заявку.</p>
          )}
        </section>
      ) : null}
      <button type="button" onClick={() => setOpen((value) => !value)} className="ox-btn ox-btn-sm ox-btn-solid" aria-expanded={open}>
        {open ? "Скрыть" : "Спросить"}
      </button>
    </div>
  );
}
