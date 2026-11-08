import Link from "next/link";
import { PasswordLogin } from "@/components/PasswordLogin";
import { TelegramCodeLogin } from "@/components/TelegramCodeLogin";

export default async function LoginPage() {
  const botUsername = process.env.NEXT_PUBLIC_BOT_USERNAME;

  return (
    <main className="prisma-auth-page prisma-liquid-bg flex min-h-svh items-center justify-center px-4 py-8">
      <div className="w-full max-w-[420px]">
        <div className="prisma-stagger mb-7 text-center">
          <Link href="/" className="mx-auto mb-4 flex size-11 items-center justify-center prisma-glass-primary rounded-xl border text-sm font-bold text-primary-foreground shadow-sm">
            P
          </Link>
          <h1 className="text-2xl font-semibold tracking-tight">Вход в PRISMA</h1>
          <p className="mt-1.5 text-sm text-muted-foreground">
            Единая панель управления экосистемой.
          </p>
        </div>

        <div className="prisma-login-card prisma-glass-surface prisma-stagger-2 rounded-xl border p-6 shadow-sm">
          {botUsername ? (
            <TelegramCodeLogin />
          ) : (
            <p className="prisma-glass-surface rounded-lg border px-3 py-2 text-xs text-muted-foreground">
              Вход через Telegram сейчас недоступен.
            </p>
          )}
          <PasswordLogin />
        </div>

        <p className="mt-6 text-center text-xs text-muted-foreground">
          PRISMA ecosystem · private administration
        </p>
      </div>
    </main>
  );
}
