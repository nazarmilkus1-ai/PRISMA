import Link from "next/link";

export const dynamic = "force-dynamic";

export default function AccessDeniedPage() {
  return (
    <main className="prisma-liquid-bg flex min-h-svh items-center justify-center px-4 py-8">
      <section className="prisma-glass-surface w-full max-w-[480px] rounded-xl border p-6 shadow-sm">
        <div className="flex size-11 items-center justify-center rounded-xl bg-destructive/10 text-lg text-destructive" aria-hidden>!</div>
        <p className="mt-5 text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">PRISMA · доступ</p>
        <h1 className="mt-2 text-2xl font-semibold tracking-tight">Нет доступа к панели</h1>
        <p className="mt-2 text-sm leading-6 text-muted-foreground">
          Эта учётная запись не привязана к активной роли персонала PRISMA. Если доступ должен быть у вас, попросите владельца проверить роль и привязку Telegram-аккаунта.
        </p>
        <div className="mt-5 flex flex-wrap gap-2">
          <Link href="/" className="prisma-glass-primary inline-flex h-10 items-center rounded-lg border px-4 text-sm font-semibold text-primary-foreground">
            Перейти ко входу
          </Link>
          <form action="/admin/api/auth/logout" method="post">
            <button type="submit" className="prisma-glass-control prisma-glass-hover inline-flex h-10 items-center rounded-lg border px-4 text-sm font-medium">
              Выйти
            </button>
          </form>
        </div>
      </section>
    </main>
  );
}
