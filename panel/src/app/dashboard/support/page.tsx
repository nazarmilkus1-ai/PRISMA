import { requireAdmin } from "@/lib/require-admin";
import { PageHeader } from "@prisma-eco/ui";
import { SupportPanel } from "@/components/SupportPanel";

export default async function SupportPage({ searchParams }: { searchParams: Promise<{ user_id?: string }> }) {
  const admin = await requireAdmin("support.manage");
  if (!admin) return null;
  const params = await searchParams;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Система"
        title="Техническая поддержка"
        description="Обращения пользователей, полная история диалога и ответы прямо из панели PRISMA."
      />
      <SupportPanel initialRecipientId={params.user_id} />
    </div>
  );
}
