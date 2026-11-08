import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { OnboardingPanel } from "@/components/OnboardingPanel";
import { STAFF_RPC } from "@prisma-eco/contracts";

export default async function OnboardingPage() {
  const admin = await requireAdmin("player.view");
  if (!admin) return null;

  const db = await createSupabaseServerClient();
  const { data: onboarding, error } = await db.rpc(STAFF_RPC.onboarding, { p_limit: 2000 });
  const onboardingUsers = Array.isArray(onboarding) ? onboarding : [];
  return (
    <div className="space-y-6">
      <div>
        <p className="font-mono text-xs uppercase tracking-[0.25em] text-curse">Onboarding</p>
        <h1 className="mt-1 font-display text-2xl text-moon">Без анкеты</h1>
        <p className="mt-1 max-w-3xl text-sm text-moon-dim">
          Пользователи, которых PRISMA уже увидел в группе, но они ещё не подали заявку.
          Людей, которые никогда не взаимодействовали с ботом в группе, невозможно автоматически найти или написать им в личные сообщения.
        </p>
      </div>
      {error && (
        <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">
          Не удалось полностью загрузить onboarding: {error.message}
        </div>
      )}
      <OnboardingPanel
        users={onboardingUsers}
        botUsername={process.env.NEXT_PUBLIC_BOT_USERNAME || "prisma_eco_bot"}
      />
    </div>
  );
}
