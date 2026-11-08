"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Card, Tabs } from "@/components/ui";
import { Modal, ConfirmModal } from "@/components/Modal";

type NewsItem = {
  id: string;
  title: string;
  body: string;
  kind: "NEWS" | "UPDATE";
  is_published: boolean;
  created_by_name: string | null;
  created_at: string;
};

export function NewsPanel({ initialNews }: { initialNews: NewsItem[] }) {
  const [filter, setFilter] = useState<"ALL" | "NEWS" | "UPDATE">("ALL");
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<NewsItem | null>(null);
  const [deleting, setDeleting] = useState<NewsItem | null>(null);
  const router = useRouter();

  const visible = filter === "ALL" ? initialNews : initialNews.filter((n) => n.kind === filter);

  async function togglePublished(item: NewsItem) {
    const res = await fetch(`/admin/api/news/${item.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isPublished: !item.is_published }),
    });
    if (res.ok) router.refresh();
  }

  async function confirmDelete() {
    if (!deleting) return;
    const res = await fetch(`/admin/api/news/${deleting.id}`, { method: "DELETE" });
    if (res.ok) {
      setDeleting(null);
      router.refresh();
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Tabs active={filter} onChange={(key) => setFilter(key as typeof filter)} tabs={[{ key: "ALL", label: "Все" }, { key: "NEWS", label: "Новости" }, { key: "UPDATE", label: "Обновления" }]} />
        <button onClick={() => setCreating(true)} className="rounded-lg bg-ember/20 px-4 py-2.5 text-sm font-medium text-ember transition-colors hover:bg-ember/30">+ Додати</button>
      </div>

      {visible.length === 0 ? (
        <Card className="p-10 text-center text-sm text-moon-dim">Нет записей.</Card>
      ) : (
        <div className="space-y-3">
          {visible.map((item) => (
            <Card key={item.id} className="p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${item.kind === "UPDATE" ? "bg-curse/15 text-curse" : "bg-ember/15 text-ember"}`}>{item.kind === "UPDATE" ? "Обновления" : "Новина"}</span>
                    {!item.is_published && <span className="rounded-full border border-border px-2 py-0.5 text-xs text-moon-dim">архив</span>}
                  </div>
                  <h3 className="mt-1.5 font-medium text-moon">{item.title}</h3>
                  <p className="mt-1 whitespace-pre-wrap text-sm text-moon-dim">{item.body}</p>
                  <p className="mt-2 text-xs text-moon-dim">{new Date(item.created_at).toLocaleDateString("ru-RU")}{item.created_by_name ? ` · ${item.created_by_name}` : ""}</p>
                </div>
                <div className="flex flex-wrap gap-1">
                  <button onClick={() => void togglePublished(item)} className="rounded-lg px-2 py-1.5 text-xs text-moon-dim hover:text-moon">{item.is_published ? "Архивировать" : "Опубликовать"}</button>
                  <button onClick={() => setEditing(item)} className="rounded-lg px-2 py-1.5 text-xs text-moon-dim hover:text-moon">Изменить</button>
                  {item.is_published && <button onClick={() => setDeleting(item)} className="rounded-lg px-2 py-1.5 text-xs text-danger/80 hover:text-danger">Архивировать</button>}
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      <Modal open={creating} onClose={() => setCreating(false)}>
        <NewsForm onDone={() => { setCreating(false); router.refresh(); }} onCancel={() => setCreating(false)} />
      </Modal>
      <Modal open={editing !== null} onClose={() => setEditing(null)}>
        {editing && <NewsForm existing={editing} onDone={() => { setEditing(null); router.refresh(); }} onCancel={() => setEditing(null)} />}
      </Modal>
      <ConfirmModal
        open={deleting !== null}
        onClose={() => setDeleting(null)}
        onConfirm={() => void confirmDelete()}
        title="Архивировать запис?"
        description={deleting ? `«${deleting.title}» исчезнет из опубликованных новостей, но останется в системе и его можно будет опубликовать снова.` : ""}
        confirmLabel="Архивировать"
        tone="ember"
      />
    </div>
  );
}

function NewsForm({ existing, onDone, onCancel }: { existing?: NewsItem; onDone: () => void; onCancel: () => void }) {
  const [title, setTitle] = useState(existing?.title ?? "");
  const [body, setBody] = useState(existing?.body ?? "");
  const [kind, setKind] = useState<"NEWS" | "UPDATE">(existing?.kind ?? "NEWS");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (title.trim().length < 2 || body.trim().length < 2) {
      setError("Заполните заголовок и текст.");
      return;
    }
    setBusy(true);
    setError(null);
    const url = existing ? `/admin/api/news/${existing.id}` : "/admin/api/news";
    const res = await fetch(url, {
      method: existing ? "PATCH" : "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: title.trim(), body: body.trim(), kind, isPublished: existing?.is_published ?? true }),
    });
    const data = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) {
      setError(data.error ?? "Не вдалося зберегти запис.");
      return;
    }
    onDone();
  }

  return (
    <div className="space-y-4">
      <h2 className="font-display text-lg text-moon">{existing ? "Изменить запис" : "Новая запись"}</h2>
      <div className="flex gap-2">
        {(["NEWS", "UPDATE"] as const).map((key) => <button key={key} onClick={() => setKind(key)} className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${kind === key ? "bg-panel-raised text-moon" : "text-moon-dim hover:text-moon"}`}>{key === "NEWS" ? "Новина" : "Обновления"}</button>)}
      </div>
      <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Заголовок" className="w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse" />
      <textarea value={body} onChange={(event) => setBody(event.target.value)} placeholder="Текст" rows={5} className="w-full resize-none rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse" />
      {error && <p className="text-sm text-danger">{error}</p>}
      <div className="flex justify-end gap-2 pt-2">
        <button onClick={onCancel} className="rounded-lg px-3 py-2 text-sm text-moon-dim hover:text-moon">Скасувати</button>
        <button onClick={() => void submit()} disabled={busy} className="rounded-lg bg-ember/20 px-4 py-2 text-sm font-medium text-ember transition-colors hover:bg-ember/30 disabled:opacity-40">{busy ? "Сохраняем…" : "Сохранить"}</button>
      </div>
    </div>
  );
}
