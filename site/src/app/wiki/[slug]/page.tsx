import { requireModule, requireModuleMember, requireModuleUser } from '@/lib/access';
import { notFound } from 'next/navigation';
import Link from 'next/link';
import { Metadata } from 'next';
import { getWiki } from '@/lib/data';
import { Card, CardContent, PageHeader, Badge, Button } from '@prisma-eco/ui';
import { Icon } from '@/components/Icon';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeSlug from 'rehype-slug';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneDark } from 'react-syntax-highlighter/dist/esm/styles/prism';

export const metadata: Metadata = {
  title: { template: '%s | PRISMA Wiki', default: 'PRISMA Wiki' },
  description: 'Документация PRISMA: Minecraft, Telegram, системы, гайды и внутренняя документация Staff.',
};

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

const CATEGORY_LABELS: Record<string, string> = {
  MINECRAFT: 'Minecraft',
  TELEGRAM: 'Telegram',
  SYSTEMS: 'Systems',
  GUIDE: 'Гайды',
  ANNOUNCEMENT: 'Анонсы',
  STAFF: 'Staff',
};

const VISIBILITY_LABELS: Record<string, string> = {
  PUBLIC: 'Публично',
  MEMBER: 'Участники',
  STAFF: 'Staff',
};

const VISIBILITY_VARIANTS: Record<string, 'success' | 'warning' | 'default' | 'secondary' | 'outline' | 'destructive'> = {
  PUBLIC: 'success',
  MEMBER: 'warning',
  STAFF: 'default',
};

interface Heading {
  level: number;
  text: string;
  id: string;
}

function extractHeadings(content: string): Heading[] {
  const headings: Heading[] = [];
  const lines = content.split('\n');
  for (const line of lines) {
    const match = line.match(/^(#{1,3})\s+(.+)$/);
    if (match) {
      const level = match[1].length;
      const text = match[2].trim();
      const id = text
        .toLowerCase()
        .replace(/[^a-z0-9а-яё\s-]/gi, '')
        .replace(/\s+/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '');
      headings.push({ level, text, id });
    }
  }
  return headings;
}

function TableOfContents({ headings }: { headings: Heading[] }) {
  if (headings.length === 0) return null;
  return (
    <Card className="sticky top-24 hidden lg:block w-64 shrink-0">
      <CardContent className="p-4">
        <h4 className="font-medium text-sm text-moon mb-3">Содержание</h4>
        <nav className="space-y-1.5 text-sm">
          {headings.map((h) => (
            <Link
              key={h.id}
              href={'#' + h.id}
              className={'block px-2 py-1 rounded transition-colors hover:bg-accent ' + (h.level === 2 ? 'font-medium' : 'ml-4 text-muted-foreground')}
            >
              {h.text}
            </Link>
          ))}
        </nav>
      </CardContent>
    </Card>
  );
}

const components = {
  h1: ({ children, id }: any) => <h1 id={id} className="text-2xl font-bold mt-8 mb-4 text-moon">{children}</h1>,
  h2: ({ children, id }: any) => <h2 id={id} className="text-xl font-semibold mt-8 mb-3 text-moon border-b border-border pb-2">{children}</h2>,
  h3: ({ children, id }: any) => <h3 id={id} className="text-lg font-semibold mt-6 mb-2 text-moon">{children}</h3>,
  p: ({ children }: any) => <p className="my-3 text-moon-dim leading-7">{children}</p>,
  ul: ({ children }: any) => <ul className="list-disc list-inside my-3 space-y-1 text-moon-dim">{children}</ul>,
  ol: ({ children }: any) => <ol className="list-decimal list-inside my-3 space-y-1 text-moon-dim">{children}</ol>,
  li: ({ children }: any ) => <li className="leading-7">{children}</li>,
  a: ({ href, children }: any) => (
    <a href={href} className="text-primary underline hover:text-primary/80" target={href.startsWith('http') ? '_blank' : undefined} rel={href.startsWith('http') ? 'noopener noreferrer' : undefined}>{children}</a>
  ),
  code: ({ children, className }: any) => {
    if (className && className.startsWith('language-')) return null;
    return <code className="prisma-glass-surface px-1.5 py-0.5 rounded text-sm font-mono text-curse bg-muted/50 border">{children}</code>;
  },
  pre: ({ children }: any) => <div className="my-4 rounded-lg overflow-hidden">{children}</div>,
  blockquote: ({ children }: any) => (
    <div className="border-l-4 border-primary/30 pl-4 my-4 italic text-moon-dim">{children}</div>
  ),
  table: ({ children }: any) => <div className="my-4 overflow-x-auto">{children}</div>,
  thead: ({ children }: any) => <thead className="bg-muted/50">{children}</thead>,
  tbody: ({ children }: any) => <tbody>{children}</tbody>,
  tr: ({ children }: any) => <tr>{children}</tr>,
  th: ({ children }: any) => <th className="px-3 py-2 text-left font-semibold text-moon border-b">{children}</th>,
  td: ({ children }: any) => <td className="px-3 py-2 text-moon-dim border-b border-border/50">{children}</td>,
  hr: () => <hr className="my-8 border-border/30" />,
};

export default async function WikiArticlePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  await requireModule('public-content');
  const pages = (await getWiki()) as WikiPage[];
  const page = pages.find((p) => p.slug === slug);

  if (!page || !page.published) notFound();

  const headings = extractHeadings(page.content);

  return (
    <div className="mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
      <div className="flex flex-col lg:flex-row gap-8">
        <div className="flex-1 min-w-0 lg:max-w-3xl">
          <div className="mb-6 flex flex-wrap items-center gap-2">
            <Badge variant={VISIBILITY_VARIANTS[page.visibility] ?? 'default'}>{VISIBILITY_LABELS[page.visibility] ?? page.visibility}</Badge>
            <Badge variant="secondary">{CATEGORY_LABELS[page.category] ?? page.category}</Badge>
            <span className="text-xs text-muted-foreground ml-auto">{new Date(page.updated_at).toLocaleDateString('ru-RU')}</span>
          </div>

          <h1 className="text-3xl font-bold text-moon mb-2">{page.title}</h1>
          {page.excerpt && <p className="text-lg text-moon-dim mb-6 leading-7">{page.excerpt}</p>}

          <article className="prose prose-lg max-w-none prose-img:rounded-xl prose-headings:text-moon prose-a:text-primary prose-a:no-underline hover:prose-a:underline">
            <ReactMarkdown
              components={components}
              remarkPlugins={[remarkGfm]}
              rehypePlugins={[rehypeSlug, [rehypeAutolinkHeadings, { behavior: 'wrap' }]]}
            >
              {page.content}
            </ReactMarkdown>
          </article>

          <div className="mt-8 pt-6 border-t border-border flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Навигация:</span>
              <Link href="/wiki" className="text-sm text-primary hover:underline">Wiki</Link>
              <Icon name="chevron-right" size={14} className="text-muted-foreground" />
              <span className="text-sm text-muted-foreground">{CATEGORY_LABELS[page.category] ?? page.category}</span>
            </div>
            <Link href="/wiki" className="rounded-lg border border-border px-4 py-2 text-sm text-moon-dim hover:text-moon hover:bg-accent">К оглавлению Wiki</Link>
          </div>
        </div>

        <aside className="hidden lg:block w-64 shrink-0">
          <TableOfContents headings={headings} />
        </aside>
      </div>
    </div>
  );
}