import { LoginForm } from "@/components/LoginForm";

export const metadata = { title: "Вход" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const params = await searchParams;
  const next = typeof params.next === "string" && params.next.startsWith("/") && !params.next.startsWith("//")
    ? params.next
    : "/app";

  return (
    <div className="prisma-page-enter mx-auto flex min-h-[calc(100vh-64px)] max-w-xl items-center px-4 py-12 sm:px-6">
      <div className="prisma-login-card prisma-glass-surface w-full rounded-3xl border p-6 shadow-sm sm:p-8">
        <p className="text-sm font-medium text-[var(--muted-foreground)]">PRISMA Community</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight">Вход в кабинет</h1>
        <p className="mt-2 text-sm leading-6 text-[var(--muted-foreground)]">Используйте тот же Telegram-аккаунт, который связан с вашим профилем PRISMA.</p>
        <div className="mt-8"><LoginForm next={next} /></div>
      </div>
    </div>
  );
}
