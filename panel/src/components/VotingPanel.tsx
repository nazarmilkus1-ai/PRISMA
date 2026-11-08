"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Card, ProgressBar } from "@/components/ui";
import { Modal } from "@/components/Modal";

type Poll = {
  id: string;
  question: string;
  options: string[];
  is_active: boolean;
  closes_at: string | null;
  created_at: string;
  votes: number[];
};

export function VotingPanel({ initialPolls }: { initialPolls: Poll[] }) {
  const [creating, setCreating] = useState(false);
  const router = useRouter();

  async function toggleActive(id: string, next: boolean) {
    await fetch(`/admin/api/polls/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isActive: next }),
    });
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <button
        onClick={() => setCreating(true)}
        className="rounded-lg bg-ember/20 px-4 py-2.5 text-sm font-medium text-ember transition-colors hover:bg-ember/30"
      >
        + Новое голосование
      </button>

      {initialPolls.length === 0 ? (
        <Card className="p-10 text-center text-sm text-moon-dim">Пока нет ни одного голосования.</Card>
      ) : (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {initialPolls.map((poll) => {
            const total = poll.votes.reduce((a, b) => a + b, 0);
            return (
              <Card key={poll.id} className="p-5">
                <div className="flex items-start justify-between gap-3">
                  <h3 className="font-medium text-moon">{poll.question}</h3>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                      poll.is_active ? "bg-success/15 text-success" : "border border-border text-moon-dim"
                    }`}
                  >
                    {poll.is_active ? "активно" : "закрыто"}
                  </span>
                </div>

                <div className="mt-4 space-y-3">
                  {poll.options.map((option, i) => (
                    <ProgressBar
                      key={i}
                      value={poll.votes[i] ?? 0}
                      max={Math.max(total, 1)}
                      tone="curse"
                      label={`${option} — ${poll.votes[i] ?? 0}`}
                    />
                  ))}
                </div>

                <div className="mt-4 flex items-center justify-between border-t border-border pt-3 text-xs text-moon-dim">
                  <span>Всего голосов: {total}</span>
                  <button
                    onClick={() => toggleActive(poll.id, !poll.is_active)}
                    className="text-moon-dim underline decoration-dotted underline-offset-4 hover:text-moon"
                  >
                    {poll.is_active ? "Закрыть" : "Открыть снова"}
                  </button>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      <Modal open={creating} onClose={() => setCreating(false)}>
        <CreatePollForm
          onDone={() => {
            setCreating(false);
            router.refresh();
          }}
          onCancel={() => setCreating(false)}
        />
      </Modal>
    </div>
  );
}

function CreatePollForm({ onDone, onCancel }: { onDone: () => void; onCancel: () => void }) {
  const [question, setQuestion] = useState("");
  const [options, setOptions] = useState(["", ""]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function updateOption(i: number, value: string) {
    setOptions((prev) => prev.map((o, idx) => (idx === i ? value : o)));
  }

  async function submit() {
    setError(null);
    const cleanOptions = options.map((o) => o.trim()).filter(Boolean);
    if (question.trim().length < 3) return setError("Слишком короткий вопрос.");
    if (cleanOptions.length < 2) return setError("Нужно минимум 2 варианта ответа.");

    setBusy(true);
    const res = await fetch("/admin/api/polls", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question: question.trim(), options: cleanOptions }),
    });
    setBusy(false);
    if (!res.ok) return setError("Не удалось создать голосование.");
    onDone();
  }

  return (
    <div className="space-y-4">
      <h2 className="font-display text-lg text-moon">Новое голосование</h2>

      <div>
        <label className="mb-1 block text-xs text-moon-dim">Вопрос</label>
        <input
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="Например: Добавить ли новый мир?"
          className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse"
        />
      </div>

      <div className="space-y-2">
        <label className="block text-xs text-moon-dim">Варианты ответа</label>
        {options.map((opt, i) => (
          <input
            key={i}
            value={opt}
            onChange={(e) => updateOption(i, e.target.value)}
            placeholder={`Вариант ${i + 1}`}
            className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse"
          />
        ))}
        {options.length < 8 && (
          <button
            onClick={() => setOptions((prev) => [...prev, ""])}
            className="text-xs text-moon-dim underline decoration-dotted underline-offset-4 hover:text-moon"
          >
            + добавить вариант
          </button>
        )}
      </div>

      {error && <p className="text-sm text-danger">{error}</p>}

      <div className="flex justify-end gap-2 pt-2">
        <button onClick={onCancel} className="rounded-lg px-3 py-2 text-sm text-moon-dim hover:text-moon">
          Отмена
        </button>
        <button
          onClick={submit}
          disabled={busy}
          className="rounded-lg bg-ember/20 px-4 py-2 text-sm font-medium text-ember transition-colors hover:bg-ember/30 disabled:opacity-40"
        >
          {busy ? "Создаём…" : "Создать"}
        </button>
      </div>
    </div>
  );
}
