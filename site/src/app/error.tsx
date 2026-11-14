"use client";

import * as Sentry from "@sentry/nextjs";
import Link from "next/link";
import { useEffect } from "react";
import { Button, buttonVariants } from "@prisma-eco/ui";

export default function RouteError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <main className="mx-auto grid min-h-[70vh] max-w-xl place-items-center px-4 py-16">
      <div className="w-full rounded-2xl border bg-card p-8 text-center">
        <h1 className="text-2xl font-bold">Не удалось загрузить страницу</h1>
        <p className="mt-2 text-sm text-muted-foreground">Это временная ошибка — попробуйте ещё раз или вернитесь на главную.</p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <Link href="/" className={buttonVariants({ variant: "outline" })}>На главную</Link>
          <Button onClick={() => reset()}>Повторить</Button>
        </div>
      </div>
    </main>
  );
}
