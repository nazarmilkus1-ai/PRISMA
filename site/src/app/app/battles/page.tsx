import { requireModuleUser } from "@/lib/access";
import { PARTICIPANT_BATTLE_RPC, PARTICIPANT_CURRENT_USER_RPC } from "@prisma-eco/contracts";
import { MinecraftNicknameAutocomplete } from "@/components/MinecraftNicknameAutocomplete";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  EmptyState,
  Field,
  Input,
  Label,
  Metric,
  PageHeader,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@prisma-eco/ui";

export const metadata = { title: "Player Battle" };

type Battle = {
  id: string;
  challenger_id: string;
  opponent_id: string;
  challenger_score: number;
  opponent_score: number;
  winner_id: string | null;
  points_awarded: number;
  status: string;
  created_at: string;
  challenger: { minecraft_nickname: string | null };
  opponent: { minecraft_nickname: string | null };
  winner: { minecraft_nickname: string | null } | null;
};

function getBattleView(battle: Battle, currentId: string) {
  const isChallenger = battle.challenger_id === currentId;
  const opponent = isChallenger
    ? battle.opponent.minecraft_nickname
    : battle.challenger.minecraft_nickname;
  const ownScore = isChallenger ? battle.challenger_score : battle.opponent_score;
  const opponentScore = isChallenger ? battle.opponent_score : battle.challenger_score;
  const delta =
    battle.winner_id === currentId
      ? battle.points_awarded
      : battle.winner_id === null
        ? 0
        : -battle.points_awarded;

  const result =
    battle.winner_id === currentId
      ? { label: "Победа", variant: "success" as const }
      : battle.winner_id === null
        ? { label: "Ничья", variant: "secondary" as const }
        : { label: "Поражение", variant: "destructive" as const };

  return { opponent, ownScore, opponentScore, delta, result };
}

function formatBattleDate(value: string, compact = false) {
  const date = new Date(value);
  return date.toLocaleString(
    "ru-RU",
    compact
      ? { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }
      : { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" },
  );
}

export default async function BattlesPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; created?: string }>;
}) {
  const user = await requireModuleUser("battles");
  const db = await createSupabaseServerClient();

  const [{ data: battlesData, error: battlesError }, { data: currentData }] =
    await Promise.all([
      db.rpc(PARTICIPANT_BATTLE_RPC.list, { p_limit: 50 }),
      db.rpc(PARTICIPANT_CURRENT_USER_RPC.get),
    ]);

  const battles =
    battlesError || !Array.isArray(battlesData) ? [] : (battlesData as Battle[]);

  const current =
    currentData && typeof currentData === "object" ? (currentData as any) : user;

  const params = await searchParams;
  const errorMessage = params.error ? decodeURIComponent(params.error) : null;

  const wins = battles.filter((battle) => battle.winner_id === current.id).length;
  const losses = battles.filter(
    (battle) => battle.winner_id !== null && battle.winner_id !== current.id,
  ).length;
  const draws = battles.filter((battle) => battle.winner_id === null).length;

  const canBattle =
    current.status === "ACCEPTED" && current.is_whitelisted && !current.is_banned;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Соревнования"
        title="Player Battle"
        description="Сравните свою статистику со статистикой другого участника. Результат рассчитывается сервером из игровых показателей и влияет на рейтинг."
      />

      {errorMessage ? (
        <p
          role="alert"
          className="prisma-glass-surface rounded-xl border border-destructive/30 px-3 py-2 text-sm text-destructive"
        >
          {errorMessage}
        </p>
      ) : null}

      {params.created ? (
        <p className="prisma-glass-surface rounded-xl border border-emerald-500/30 px-3 py-2 text-sm text-emerald-700 dark:text-emerald-300">
          Бой завершён. Результат добавлен в историю.
        </p>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-3">
        <Metric label="Победы" value={wins} hint="в вашей истории" icon="activity" />
        <Metric label="Поражения" value={losses} hint="в вашей истории" icon="bar-chart" />
        <Metric label="Ничьи" value={draws} hint="без изменения рейтинга" icon="activity" />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Новый бой</CardTitle>
          <CardDescription>
            С одним и тем же игроком можно провести не более одного боя за 24 часа.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {canBattle ? (
            <form
              action="/api/battles"
              method="post"
              className="flex flex-col gap-3 sm:flex-row sm:items-end"
            >
              <Field className="min-w-0 flex-1">
                <Label htmlFor="opponent">Minecraft-ник соперника</Label>
                <MinecraftNicknameAutocomplete
                  id="opponent"
                  name="opponent"
                  placeholder="Например, Player"
                  maxLength={16}
                  required
                  autoComplete="off"
                />
              </Field>
              <Button type="submit" size="lg">
                Начать бой
              </Button>
            </form>
          ) : (
            <div className="prisma-glass-surface rounded-md border p-4 text-sm">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="warning">Недоступно</Badge>
                <span>
                  Для Player Battle нужен принятый профиль, whitelist и отсутствие активного бана.
                </span>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>История боёв</CardTitle>
          <CardDescription>
            Здесь отображаются только бои, в которых вы участвовали.
          </CardDescription>
        </CardHeader>

        {battles.length ? (
          <>
            <div className="hidden md:block">
              <Table className="border-t">
                <TableHeader>
                  <TableRow>
                    <TableHead>Дата</TableHead>
                    <TableHead>Соперник</TableHead>
                    <TableHead>Счёт</TableHead>
                    <TableHead>Результат</TableHead>
                    <TableHead className="text-right">Изменение</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {battles.map((battle) => {
                    const view = getBattleView(battle, current.id);

                    return (
                      <TableRow key={battle.id}>
                        <TableCell className="whitespace-nowrap text-xs text-muted-foreground">
                          {formatBattleDate(battle.created_at)}
                        </TableCell>
                        <TableCell className="font-medium">
                          {view.opponent || "—"}
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {view.ownScore} : {view.opponentScore}
                        </TableCell>
                        <TableCell>
                          <Badge variant={view.result.variant}>{view.result.label}</Badge>
                        </TableCell>
                        <TableCell
                          className={[
                            "text-right font-semibold tabular-nums",
                            view.delta > 0
                              ? "text-primary"
                              : view.delta < 0
                                ? "text-destructive"
                                : "text-muted-foreground",
                          ].join(" ")}
                        >
                          {view.delta > 0 ? "+" : ""}
                          {view.delta}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>

            <div className="divide-y border-t md:hidden">
              {battles.map((battle) => {
                const view = getBattleView(battle, current.id);

                return (
                  <div key={battle.id} className="px-4 py-4">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-semibold">{view.opponent || "—"}</p>
                        <p className="mt-1 text-xs text-muted-foreground">
                          {formatBattleDate(battle.created_at, true)}
                        </p>
                      </div>
                      <Badge variant={view.result.variant}>{view.result.label}</Badge>
                    </div>

                    <div className="prisma-glass-surface mt-3 flex items-center justify-between rounded-xl border px-3 py-2.5">
                      <div>
                        <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                          Счёт
                        </p>
                        <p className="mt-0.5 font-semibold tabular-nums">
                          {view.ownScore} : {view.opponentScore}
                        </p>
                      </div>
                      <div className="text-right">
                        <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                          Изменение
                        </p>
                        <p
                          className={[
                            "mt-0.5 font-semibold tabular-nums",
                            view.delta > 0
                              ? "text-primary"
                              : view.delta < 0
                                ? "text-destructive"
                                : "text-muted-foreground",
                          ].join(" ")}
                        >
                          {view.delta > 0 ? "+" : ""}
                          {view.delta}
                        </p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </>
        ) : (
          <CardContent>
            <EmptyState
              title="История пока пуста"
              description="После первого Player Battle результат появится здесь."
            />
          </CardContent>
        )}
      </Card>
    </div>
  );
}
