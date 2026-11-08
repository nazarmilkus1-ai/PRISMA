import { requireModuleMember } from "@/lib/access";
import Link from "next/link";
import { Badge, Card, CardContent, Input, PageHeader, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@prisma-eco/ui";
import { getPlayers } from "@/lib/data";

export const metadata = { title: "Игроки" };

export default async function PlayersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  await requireModuleMember("players");
  const { q = "" } = await searchParams;
  const players = await getPlayers(q, 300);

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Сообщество"
        title="Игроки"
        description="Участники PRISMA и их публичная игровая статистика."
      />

      <Card>
        <CardContent>
          <form className="flex max-w-xl gap-2" action="/players">
            <Input name="q" defaultValue={q} placeholder="Поиск по Minecraft-нику" />
            <button
              className="prisma-glass-control prisma-glass-hover h-9 shrink-0 rounded-md border px-3 text-sm font-medium"
              type="submit"
            >
              Найти
            </button>
          </form>
        </CardContent>
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b px-5 py-4">
          <div className="flex items-center justify-between gap-3">
            <p className="text-sm font-semibold">{players.length} игроков</p>
            <Badge variant="secondary">Рейтинг</Badge>
          </div>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Игрок</TableHead>
              <TableHead>Клан</TableHead>
              <TableHead>Рейтинг</TableHead>
              <TableHead>Платформа</TableHead>
            </TableRow>
          </TableHeader>

          <TableBody>
            {players.map((p: any) => (
              <TableRow key={p.id} className="prisma-glass-hover">
                <TableCell>
                  <Link
                    href={"/players/" + encodeURIComponent(p.minecraft_nickname)}
                    className="font-medium hover:underline"
                  >
                    {p.minecraft_nickname}
                  </Link>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {p.platform || "Не указана"} · Activity {p.activity_score ?? 0}
                  </p>
                </TableCell>
                <TableCell>{p.clan_id ? "Участник клана" : "—"}</TableCell>
                <TableCell className="font-medium">{p.rating ?? 0}</TableCell>
                <TableCell>{p.platform || "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        {players.length === 0 ? (
          <CardContent>
            <p className="text-sm text-muted-foreground">Игроков по запросу не найдено.</p>
          </CardContent>
        ) : null}
      </Card>
    </div>
  );
}
