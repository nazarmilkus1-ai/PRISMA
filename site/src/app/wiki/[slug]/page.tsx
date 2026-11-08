import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Card, CardDescription, CardHeader, CardTitle } from "@prisma-eco/ui";
import { getWiki } from "@/lib/data";
import WikiReactionBar from "@/components/WikiReactionBar";

function renderInline(value: string) {
  const tick = String.fromCharCode(96);
  const token = new RegExp(
    "(\\*\\*[^*]+\\*\\*|" +
      tick + "[^" + tick + "]+" + tick +
      "|\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\))",
    "g",
  );

  return value.split(token).map((part, index) => {
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={index}>{part.slice(2, -2)}</strong>;
    }
    if (part.startsWith(tick) && part.endsWith(tick)) {
      return (
        <code
          key={index}
          className="rounded-md border bg-muted px-1.5 py-0.5 font-mono text-[0.9em] text-foreground"
        >
          {part.slice(1, -1)}
        </code>
      );
    }

    const linkMatch = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
    if (linkMatch) {
      const [, label, href] = linkMatch;
      const safeHref =
        href.startsWith("/") || /^https?:\/\//i.test(href)
          ? href
          : null;

      if (safeHref) {
        if (safeHref.startsWith("/")) {
          return (
            <Link key={index} href={safeHref} className="text-primary underline-offset-4 hover:underline">
              {label}
            </Link>
          );
        }

        return (
          <a
            key={index}
            href={safeHref}
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            {label}
          </a>
        );
      }
    }

    return <span key={index}>{part}</span>;
  });
}

function splitTableRow(value: string) {
  const raw = value.trim().replace(/^\|/, "").replace(/\|$/, "");
  return raw.split("|").map((cell) => cell.trim());
}

function isTableSeparator(value: string) {
  const cells = splitTableRow(value);
  return cells.length > 0 && cells.every((cell) => /^:?-{3,}:?$/.test(cell));
}

function renderWikiContent(content: string) {
  const normalizedContent = content.replace(/\r\n?/g, "\n").trim();

  return normalizedContent.split(/\n{2,}/).map((rawBlock, index) => {
    const block = rawBlock.trim();
    const lines = block.split("\n");

    if (block.trim() === "---") {
      return <hr key={index} className="my-8 border-border" />;
    }

    if (lines.length >= 2 && lines[0].includes("|") && isTableSeparator(lines[1])) {
      const headers = splitTableRow(lines[0]);
      const rows = lines.slice(2).filter((line) => line.includes("|")).map(splitTableRow);

      return (
        <div key={index} className="my-6 overflow-x-auto rounded-lg border">
          <table className="min-w-full border-collapse text-sm">
            <thead className="bg-muted/40">
              <tr>
                {headers.map((cell, cellIndex) => (
                  <th key={cellIndex} className="border-b px-4 py-3 text-left font-semibold">
                    {renderInline(cell)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, rowIndex) => (
                <tr key={rowIndex} className="border-b last:border-b-0">
                  {headers.map((_, cellIndex) => (
                    <td key={cellIndex} className="px-4 py-3 align-top text-muted-foreground">
                      {renderInline(row[cellIndex] ?? "")}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }

    if (lines.every((line) => /^\d+\.\s/.test(line))) {
      return (
        <ol key={index} className="my-5 list-decimal space-y-2 pl-6 text-sm leading-7 text-muted-foreground">
          {lines.map((line, itemIndex) => (
            <li key={itemIndex}>{renderInline(line.replace(/^\d+\.\s/, ""))}</li>
          ))}
        </ol>
      );
    }

    if (block.startsWith("### ")) {
      return (
        <h3 key={index} className="mt-9 text-lg font-semibold tracking-tight text-foreground">
          {renderInline(block.slice(4))}
        </h3>
      );
    }
    if (block.startsWith("## ")) {
      return (
        <h2 key={index} className="mt-10 text-xl font-semibold tracking-tight text-foreground">
          {renderInline(block.slice(3))}
        </h2>
      );
    }
    if (block.startsWith("# ")) {
      return null;
    }

    if (lines.every((line) => line.startsWith("- "))) {
      return (
        <ul key={index} className="my-5 list-disc space-y-2 pl-6 text-sm leading-7 text-muted-foreground">
          {lines.map((line, itemIndex) => (
            <li key={itemIndex}>{renderInline(line.slice(2))}</li>
          ))}
        </ul>
      );
    }

    if (lines.every((line) => line.startsWith("> "))) {
      return (
        <blockquote
          key={index}
          className="my-6 rounded-r-lg border-l-2 border-brand/50 bg-muted/40 px-4 py-3 text-muted-foreground"
        >
          {lines.map((line, lineIndex) => (
            <span key={lineIndex}>
              {renderInline(line.slice(2))}
              {lineIndex < lines.length - 1 ? <br /> : null}
            </span>
          ))}
        </blockquote>
      );
    }

    return (
      <p key={index} className="my-4 text-sm leading-7 text-muted-foreground">
        {lines.map((line, lineIndex) => (
          <span key={lineIndex}>
            {renderInline(line)}
            {lineIndex < lines.length - 1 ? <br /> : null}
          </span>
        ))}
      </p>
    );
  });
}

export default async function WikiArticle({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  await requireModule("public-content");
  const pages = await getWiki();
  const page = pages.find((x: any) => x.slug === slug);

  if (!page) return notFound();

  const isStaff = page.category === "STAFF";

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6 sm:py-8">
      <div className="mb-4">
        <Link
          href={isStaff ? "/wiki?category=STAFF" : "/wiki"}
          className="prisma-glass-control prisma-glass-hover inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium text-muted-foreground"
        >
          ← {isStaff ? "К Staff" : "К Wiki"}
        </Link>
      </div>

      <Card>
        <CardHeader>
          <p className="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">{page.category}</p>
          <CardTitle className="text-2xl sm:text-3xl">{page.title}</CardTitle>
          {page.excerpt ? <CardDescription className="max-w-3xl leading-6">{page.excerpt}</CardDescription> : null}
        </CardHeader>

        <div className="px-5 py-2 pb-8 sm:px-8">
          <div className="max-w-3xl text-sm">{renderWikiContent(page.content)}</div>
          <WikiReactionBar slug={slug} />
        </div>
      </Card>
    </div>
  );
}
