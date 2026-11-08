import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card } from "@/components/Card";
import { getDashboardData, getRankingEntry } from "@/lib/data";
import { StatCard } from "@/components/SitePrimitives";

export const metadata = { title: "Моя статистика" };

function metric(label:string,value:string|number,hint?:string){
  return <Card className="p-5"><p className="text-xs text-[var(--muted-foreground)]">{label}</p><p className="mt-2 text-3xl font-semibold">{value}</p>{hint&&<p className="mt-1 text-xs text-[var(--muted-foreground)]">{hint}</p>}</Card>;
}

export default async function MinecraftPage() {
  const user = await requireModuleUser("minecraft");
  const [data, rankEntry] = await Promise.all([getDashboardData(), getRankingEntry(user.id, "rating")]);
  const s:any = data.stats || {};
  const playtime = Number(s.playtime_minutes || 0);
  const kills = Number(s.kills || 0), deaths = Number(s.deaths || 0);
  const kd = deaths ? (kills/deaths).toFixed(2) : String(kills);
  const blocks = Number(s.blocks_placed||0) + Number(s.blocks_broken||0);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-[var(--primary)]">STATISTICS</p><h1 className="mt-1 text-3xl font-semibold">Моя статистика</h1><p className="mt-1 text-sm text-[var(--muted-foreground)]">Полный набор доступных показателей игрока, разбитый по смысловым уровням.</p></div>
        <div className="flex flex-wrap gap-2"><Link href="/app/commands" className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-medium">Команды Minecraft →</Link><Link href="/app/rankings?category=rating" className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-medium">{rankEntry ? "Место #"+rankEntry.rank+" в рейтинге →" : "Рейтинги →"}</Link></div>
      </div>

      <section>
        <div className="mb-3"><h2 className="text-sm font-semibold">1 · Итоги аккаунта</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Главные показатели, которые используются в PRISMA.</p></div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <StatCard label="Rating" value={user.rating||0} caption={rankEntry ? "#"+rankEntry.rank+" место" : "позиция не рассчитана"}/>
          <StatCard label="Activity" value={user.activity_score||0} caption="активность"/>
          <StatCard label="Level" value={user.level||1} caption={(user.xp||0)+" XP"}/>
          <StatCard label="Achievements" value={data.achievements.length} caption="разблокировано"/>
          <StatCard label="Клан" value={data.clan ? "["+data.clan.tag+"]" : "—"} caption={data.clan?.name||"без клана"}/>
        </div>
      </section>

      <section>
        <div className="mb-3"><h2 className="text-sm font-semibold">2 · Бой</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">PvP/PvE, смерти и урон.</p></div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {metric("Убийства",kills)}
          {metric("Смерти",deaths)}
          {metric("K/D",kd,"отношение убийств к смертям")}
          {metric("Урон нанесён",Number(s.damage_dealt||0))}
          {metric("Урон получен",Number(s.damage_taken||0))}
        </div>
      </section>

      <section>
        <div className="mb-3"><h2 className="text-sm font-semibold">3 · Мир и прогресс</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Строительство, добыча, мобы и перемещения.</p></div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{metric("Блоков поставлено",s.blocks_placed||0)}{metric("Блоков сломано",s.blocks_broken||0)}{metric("Блоков всего",blocks)}{metric("Мобов убито",s.mobs_killed||0)}</div>
        <Card className="mt-3 p-5"><div className="grid gap-4 sm:grid-cols-2"><div><p className="text-xs text-[var(--muted-foreground)]">Пройденная дистанция</p><p className="mt-2 text-2xl font-semibold">{Number(s.distance_walked||0)}</p></div><div><p className="text-xs text-[var(--muted-foreground)]">Общий прогресс строительства/добычи</p><p className="mt-2 text-2xl font-semibold">{blocks.toLocaleString("ru-RU")} действий</p></div></div></Card>
      </section>

      <section>
        <div className="mb-3"><h2 className="text-sm font-semibold">4 · Время и актуальность</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Когда статистика обновлялась и сколько вы играли.</p></div>
        <div className="grid gap-3 sm:grid-cols-3">{metric("Игровое время",Math.floor(playtime/60)+" ч "+(playtime%60)+" мин")}{metric("Последнее обновление",s.updated_at?new Date(s.updated_at).toLocaleString("ru-RU"):"—")}{metric("Последний вход",user.last_login_at?new Date(user.last_login_at).toLocaleString("ru-RU"):"—")}</div>
      </section>
    </div>
  );
}
