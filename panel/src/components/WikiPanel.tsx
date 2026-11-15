'use client';
import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Card, Tabs, Badge, Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogDescription, DialogOverlay, DialogPortal, DialogClose, Input, Button } from '@prisma-eco/ui';
import { Icon } from '@prisma-eco/ui';

type WikiPage = {
  id: string;
  slug: string;
  title: string;
  excerpt: string | null;
  content: string;
  category: string;
  visibility: string;
  published: boolean;
  created_at: string;
  updated_at: string;
};

const VISIBILITY_LABELS: Record<string, string> = {
  PUBLIC: 'Публично',
  MEMBER: 'Участники',
  STAFF: 'Staff',
};

const VISIBILITY_VARIANTS: Record<string, 'success' | 'warning' | 'destructive' | 'default'> = {
  PUBLIC: 'success',
  MEMBER: 'warning',
  STAFF: 'destructive',
};

export function WikiPanel({ initialPages }: { initialPages: WikiPage[] }) {
  const [filter, setFilter] = useState<'ALL' | 'PUBLIC' | 'MEMBER' | 'STAFF'>('ALL');
  const [search, setSearch] = useState('');
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<WikiPage | null>(null);
  const [deleting, setDeleting] = useState<WikiPage | null>(null);
  const router = useRouter();

  const visible = initialPages.filter((page) => {
    if (filter !== 'ALL' && page.visibility !== filter) return false;
    if (search) {
      const q = search.toLowerCase();
      return (
        page.title.toLowerCase().includes(q) ||
        page.slug.toLowerCase().includes(q) ||
        (page.excerpt?.toLowerCase().includes(q) ?? false) ||
        page.category.toLowerCase().includes(q)
      );
    }
    return true;
  });

  async function togglePublished(item: WikiPage) {
    const res = await fetch('/admin/api/wiki/' + item.id, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ published: !item.published }),
    });
    if (res.ok) router.refresh();
  }

  async function confirmDelete() {
    if (!deleting) return;
    const res = await fetch('/admin/api/wiki/' + deleting.id, { method: 'DELETE' });
    if (res.ok) {
      setDeleting(null);
      router.refresh();
    }
  }

  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center justify-between gap-3'>
        <div className='flex flex-wrap gap-2'>
          <Tabs
            active={filter}
            onChange={(key) => setFilter(key as typeof filter)}
            tabs={[
              { key: 'ALL', label: 'Все' },
              { key: 'PUBLIC', label: 'Публично' },
              { key: 'MEMBER', label: 'Участники' },
              { key: 'STAFF', label: 'Staff' },
            ]}
          />
        </div>
        <div className='flex-1 min-w-[200px] max-w-md'>
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder='Поиск по заголовку, slug, категории...' />
        </div>
        <Button variant='outline' onClick={() => setCreating(true)}>+ Добавить</Button>
      </div>

      {visible.length === 0 ? (
        <Card className='p-10 text-center text-sm text-moon-dim'>Нет страниц.</Card>
      ) : (
        <div className='space-y-3'>
          {visible.map((item) => (
            <Card key={item.id} className='p-5'>
              <div className='flex flex-wrap items-start justify-between gap-3'>
                <div className='min-w-0'>
                  <div className='flex flex-wrap items-center gap-2'>
                    <Badge variant={VISIBILITY_VARIANTS[item.visibility] ?? 'default'}>{VISIBILITY_LABELS[item.visibility] ?? item.visibility}</Badge>
                    {!item.published && <Badge variant='default'>Черновик</Badge>}
                  </div>
                  <h3 className='mt-1.5 font-medium text-moon'>{item.title}</h3>
                  <p className='mt-1 text-xs text-moon-dim'>{item.category} · {item.slug}</p>
                  <p className='mt-1 whitespace-pre-wrap text-sm text-moon-dim'>{item.excerpt || item.content.slice(0, 180)}</p>
                  <p className='mt-2 text-xs text-moon-dim'>{new Date(item.updated_at).toLocaleDateString('ru-RU')}</p>
                </div>
                <div className='flex flex-wrap gap-1'>
                  <Button variant='ghost' size='sm' onClick={() => void togglePublished(item)}>{item.published ? 'В черновик' : 'Опубликовать'}</Button>
                  <Button variant='ghost' size='sm' onClick={() => setEditing(item)}>Изменить</Button>
                  {item.published && <Button variant='destructive' size='sm' onClick={() => setDeleting(item)}>Архивировать</Button>}
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={creating} onOpenChange={(open) => setCreating(open)}>
        <DialogPortal>
          <DialogOverlay />
          <DialogContent className='max-w-2xl max-h-[90vh] overflow-y-auto'>
            <DialogHeader>
              <DialogTitle>Новая страница</DialogTitle>
            </DialogHeader>
            <WikiForm onDone={() => { setCreating(false); router.refresh(); }} onCancel={() => setCreating(false)} />
            <DialogFooter>
              <Button variant='outline' onClick={() => setCreating(false)}>Отмена</Button>
            </DialogFooter>
          </DialogContent>
        </DialogPortal>
      </Dialog>

      <Dialog open={editing !== null} onOpenChange={(open) => { if (!open) setEditing(null); }}>
        <DialogPortal>
          <DialogOverlay />
          <DialogContent className='max-w-2xl max-h-[90vh] overflow-y-auto'>
            <DialogHeader>
              <DialogTitle>Изменить страницу</DialogTitle>
            </DialogHeader>
            {editing && <WikiForm existing={editing} onDone={() => { setEditing(null); router.refresh(); }} onCancel={() => setEditing(null)} />}
            <DialogFooter>
              <Button variant='outline' onClick={() => setEditing(null)}>Отмена</Button>
            </DialogFooter>
          </DialogContent>
        </DialogPortal>
      </Dialog>

      <Dialog open={deleting !== null} onOpenChange={(open) => { if (!open) setDeleting(null); }}>
        <DialogPortal>
          <DialogOverlay />
          <DialogContent className='max-w-md'>
            <DialogHeader>
              <DialogTitle>Архивировать страницу?</DialogTitle>
              <DialogDescription>{deleting ? deleting.slug + ' исчезнет из публичного Wiki, но останется в системе и её можно будет опубликовать снова.' : ''}</DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button variant='outline' onClick={() => setDeleting(null)}>Отмена</Button>
              <Button variant='destructive' onClick={() => void confirmDelete()}>Архивировать</Button>
            </DialogFooter>
          </DialogContent>
        </DialogPortal>
      </Dialog>
    </div>
  );
}

function WikiForm({ existing, onDone, onCancel }: { existing?: WikiPage; onDone: () => void; onCancel: () => void }) {
  const [slug, setSlug] = useState(existing?.slug ?? '');
  const [title, setTitle] = useState(existing?.title ?? '');
  const [excerpt, setExcerpt] = useState(existing?.excerpt ?? '');
  const [content, setContent] = useState(existing?.content ?? '');
  const [category, setCategory] = useState(existing?.category ?? '');
  const [published, setPublished] = useState(existing?.published ?? false);
  const [visibility, setVisibility] = useState<'PUBLIC' | 'MEMBER' | 'STAFF'>(existing?.visibility as any ?? 'PUBLIC');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!slug.trim() || !title.trim() || !content.trim() || !category.trim()) {
      setError('Заполните обязательные поля: slug, заголовок, контент, категория.');
      return;
    }
    if (!/^[a-z0-9-]+$/.test(slug.trim())) {
      setError('Slug может содержать только строчные буквы, цифры и дефисы.');
      return;
    }
    setBusy(true);
    setError(null);
    const url = existing ? '/admin/api/wiki/' + existing.id : '/admin/api/wiki';
    const res = await fetch(url, {
      method: existing ? 'PATCH' : 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        slug: slug.trim(),
        title: title.trim(),
        excerpt: excerpt.trim() || null,
        content: content.trim(),
        category: category.trim().toUpperCase(),
        published,
        visibility,
      }),
    });
    const data = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) {
      setError(data.error ?? 'Не удалось сохранить страницу.');
      return;
    }
    onDone();
  }

  return (
    <div className='space-y-4 max-w-2xl p-4'>
      <div className='grid gap-3 sm:grid-cols-2'>
        <Input value={slug} onChange={(e) => setSlug(e.target.value)} placeholder='slug (a-z, 0-9, -)' disabled={!!existing} />
        <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder='Заголовок' />
      </div>
      <div className='grid gap-3 sm:grid-cols-2'>
        <select value={category} onChange={(e) => setCategory(e.target.value)} className='w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse'>
          <option value=''>Категория</option>
          <option value='MINECRAFT'>MINECRAFT</option>
          <option value='TELEGRAM'>TELEGRAM</option>
          <option value='SYSTEMS'>SYSTEMS</option>
          <option value='GUIDE'>GUIDE</option>
          <option value='ANNOUNCEMENT'>ANNOUNCEMENT</option>
          <option value='STAFF'>STAFF</option>
        </select>
        <select value={visibility} onChange={(e) => setVisibility(e.target.value as any)} className='w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse'>
          <option value='PUBLIC'>Публично</option>
          <option value='MEMBER'>Участники</option>
          <option value='STAFF'>Staff</option>
        </select>
      </div>
      <Input value={excerpt} onChange={(e) => setExcerpt(e.target.value)} placeholder='Краткое описание (до 500 символов)' maxLength={500} />
      <textarea value={content} onChange={(e) => setContent(e.target.value)} placeholder='Контент (Markdown)' rows={10} className='w-full resize-none rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse font-mono' />
      <div className='flex items-center gap-3'>
        <label className='flex items-center gap-2 text-sm text-moon'>
          <input type='checkbox' checked={published} onChange={(e) => setPublished(e.target.checked)} className='rounded border-border' />
          Опубликовать сразу
        </label>
      </div>
      {error && <p className='text-sm text-danger'>{error}</p>}
      <div className='flex justify-end gap-2 pt-2'>
        <Button variant='outline' onClick={onCancel}>Отмена</Button>
        <Button onClick={() => void submit()} disabled={busy}>{busy ? 'Сохраняем…' : 'Сохранить'}</Button>
      </div>
    </div>
  );
}
