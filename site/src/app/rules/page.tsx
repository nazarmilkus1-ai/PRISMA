import { Card } from "@/components/Card";

export const metadata = { title: "Правила" };

export default function RulesPage() {
  return (
    <div className="mx-auto max-w-4xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-semibold">Правила PRISMA</h1>
      <p className="mt-2 text-[var(--muted-foreground)]">Перед игрой ознакомьтесь с основными правилами сообщества.</p>
      <div className="mt-8 space-y-4">
        {[
          ["Уважение", "Не мешайте другим игрокам, не провоцируйте конфликты и соблюдайте решения модерации."],
          ["Честная игра", "Не используйте читы, эксплойты и другие способы получения нечестного преимущества."],
          ["Сообщество", "Сохраняйте нормальную атмосферу в Telegram и на сервере."],
          ["Контент", "Не распространяйте запрещённый или опасный контент через инфраструктуру PRISMA."],
        ].map(([title, body]) => (
          <Card key={title} className="p-5"><h2 className="font-semibold">{title}</h2><p className="mt-2 text-sm leading-6 text-[var(--muted-foreground)]">{body}</p></Card>
        ))}
      </div>
    </div>
  );
}
