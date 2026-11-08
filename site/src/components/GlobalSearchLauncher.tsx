"use client";

import { useEffect, useRef, useState } from "react";
import { Button, Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@prisma-eco/ui";
import { Icon } from "@/components/Icon";

export function GlobalSearchLauncher() {
  const [open, setOpen] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      const typing = tag === "input" || tag === "textarea" || tag === "select" || target?.isContentEditable;
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen(true);
        return;
      }
      if (event.key === "/" && !typing && !event.ctrlKey && !event.metaKey && !event.altKey) {
        event.preventDefault();
        setOpen(true);
      }
    };

    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, []);

  useEffect(() => {
    if (!open) return;
    const timer = window.setTimeout(() => inputRef.current?.focus(), 30);
    return () => window.clearTimeout(timer);
  }, [open]);

  return (
    <>
      <Button
        type="button"
        variant="outline"
        size="sm"
        onClick={() => setOpen(true)}
        iconLeft={<Icon name="search" size={15} />}
        className="prisma-glass-control prisma-glass-hover min-w-0 justify-start text-muted-foreground sm:min-w-44"
        aria-label="Открыть глобальный поиск"
      >
        <span className="hidden flex-1 text-left sm:inline">Поиск по PRISMA</span>
        <kbd className="hidden rounded border bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground md:inline">
          Ctrl K
        </kbd>
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <div>
              <DialogTitle>Глобальний пошук</DialogTitle>
              <DialogDescription>
                Игроки, кланы, новости, Wiki и объявления PRISMA.
              </DialogDescription>
            </div>
          </DialogHeader>
          <form action="/search" method="get" className="space-y-3">
            <input
              ref={inputRef}
              name="q"
              type="search"
              autoComplete="off"
              maxLength={100}
              placeholder="Например: xN4ZARx, кланы, ферма..."
              aria-label="Поисковый запрос"
              className="prisma-glass-control flex h-10 w-full rounded-md border px-3 text-sm shadow-sm outline-none transition-colors placeholder:text-muted-foreground focus:border-ring focus:ring-2 focus:ring-ring/30"
            />
            <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
              <span>Enter — открыть результаты</span>
              <span>Esc — закрыть</span>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}