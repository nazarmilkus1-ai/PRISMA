import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import { getAnalyticsData } from "@/lib/data";
import { Card } from "@/components/Card";
import { SectionTitle } from "@/components/SitePrimitives";

type Period = "24h" | "7d" | "30d" | "all";
const PERIODS: [Period, string][] = [["24h", "24 ч"], ["7d", "7 дн."], ["30d", "30 дн."], ["all", "Всё"]];

function metric(label:string,value:string|number,hint?:string){
  return <Card className="p-5"><p className="text-xs text-[var(--muted-foreground)]">{label}</p><p className="mt-2 text-2xl font-semibold">{value}</p>{hint&&<p className="mt-1 text-xs text-[var(--muted-foreground)]">{hint}</p>}</Card>;
}
function Bar({value,max}:{value:number;max:number}){const width=max?Math.max(2,Math.round(value/max*100)):2;return <div className="h-2 overflow-hidden rounded-full bg-[var(--muted)]"><div className="h-full rounded-full bg-[var(--primary)]" style={{width:width+"%"}}/></div>}
function normalizePeriod(value:string|undefined):Period{return value==="24h"||value==="7d"||value==="30d"||value==="all"?value:"30d";}
function periodLabel(period:Period){return period==="24h"?"24 часа":period==="7d"?"7 дней":period==="30d"?"30 дней":"всё время";}

export const metadata={title:"Аналитика"};

export default async function HistoryPage({searchParams}:{searchParams:Promise<{period?:string;detail?:string}>}){
  const me = await requireModuleMember("analytics");
  const sp=await searchParams;
  const period=normalizePeriod(sp.period);
  const detailed=sp.detail==="1";
  const data=await getAnalyticsData(period);
  if(!data) return <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6"><Card className="p-10 text-center"><p className="font-semibold">Аналитика временно недоступна.</p><p className="mt-1 text-sm text-[var(--muted-foreground)]">Не удалось загрузить данные PRISMA.</p></Card></div>;

  const server=data.server||{},community=data.community||{},stats=data.stats||{};
  const totalPlayers=Number(community.total_players||0),activePlayers=Number(community.active_players||0);
  const totalKills=Number(stats.kills||0),totalDeaths=Number(stats.deaths||0),totalPlaytime=Number(stats.playtime_minutes||0);
  const totalBlocksPlaced=Number(stats.blocks_placed||0),totalBlocksBroken=Number(stats.blocks_broken||0);
  const totalMobs=Number(stats.mobs_killed||0),totalDistance=Number(stats.distance_walked||0);
  const totalDamage=Number(stats.damage_dealt||0),totalDamageTaken=Number(stats.damage_taken||0);
  const totalXp=Number(community.total_xp||0),avgRating=Number(community.average_rating||0);
  const avgLevel=Number(community.average_level||0);
  const kd=totalDeaths?(totalKills/totalDeaths).toFixed(2):String(totalKills);
  const serverPeak=Number(server.peak_online||0),avgOnline=Number(server.average_online||0);
  const avgTps=server.average_tps==null?"—":Number(server.average_tps).toFixed(1);
  const currentOnline=Number(server.current_online||0),currentMemory=server.current_memory_mb;
  const peakMemory=Number(server.peak_memory_mb||0);
  const serverRows=(data.telemetry||[]) as any[];
  const chatRows=(data.chatActivity||[]) as any[];
  const myChat=(data.myChat||[]) as any[];
  const ratingTop=(data.ratingTop||[]) as any[],killTop=(data.killsTop||[]) as any[];
  const maxRating=Math.max(1,...ratingTop.map(p=>Number(p.value||0)));
  const maxKills=Math.max(1,...killTop.map(p=>Number(p.value||0)));
  const maxOnline=Math.max(1,...serverRows.map((r:any)=>Number(r.online_players||0)));
  const maxChat=Math.max(1,...chatRows.map((r:any)=>Number(r.messages||0)));

  return (
    <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
    <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
      <SectionTitle eyebrow="SERVER & COMMUNITY" title="Аналитика" description={`Данные за ${periodLabel(period)}. Агрегаты меняются вместе с выбранным периодом.`}/>
      <div className="prisma-glass-surface flex flex-wrap items-center gap-1 rounded-xl border p-1">
        {PERIODS.map(([value,label])=><Link key={value} href={`/app/history?period=${value}${detailed?"&detail=1":""}`} className={`prisma-glass-hover rounded-lg px-3 py-1.5 text-xs font-medium ${period===value?"border border-[var(--primary)]/35 text-[var(--foreground)] shadow-sm":"text-[var(--muted-foreground)]"}`}>{label}</Link>)}
        <Link href={`/app/history?period=${period}${detailed?"":"&detail=1"}`} className={`prisma-glass-hover rounded-lg px-3 py-1.5 text-xs font-medium ${detailed?"border border-[var(--primary)]/35 text-[var(--primary)]":"text-[var(--muted-foreground)]"}`}>{detailed?"Сводка":"Детально"}</Link>
      </div>
    </div>

    <section className="mt-5">
      <div className="mb-3"><h2 className="text-sm font-semibold">1 · Сервер</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Сводные показатели нагрузки и онлайна за выбранный период.</p></div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
        {metric("Текущий online",currentOnline,"последнее измерение")}
        {metric("Пик online",serverPeak,`за ${periodLabel(period)}`)}
        {metric("Средний online",avgOnline,`за ${periodLabel(period)}`)}
        {metric("Средний TPS",avgTps,`за ${periodLabel(period)}`)}
        {metric("Память сейчас",currentMemory!=null?Number(currentMemory)+" MB":"—")}
        {metric("Пик памяти",peakMemory?peakMemory+" MB":"—",`за ${periodLabel(period)}`)}
      </div>
    </section>

    <div className="mt-4 grid gap-4 xl:grid-cols-2">
      <Card className="p-5">
        <div className="mb-4"><h2 className="font-semibold">Онлайн · динамика</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Агрегированные значения за выбранный период.</p></div>
        <div className="flex h-32 items-end gap-1 overflow-hidden">{serverRows.map((r:any,i:number)=><div key={i} className="min-w-1 flex-1 rounded-t-sm bg-[var(--primary)]" style={{height:Math.max(4,Number(r.online_players||0)/maxOnline*100)+"%"}} title={new Date(r.recorded_at).toLocaleString("ru-RU")+" · "+r.online_players}/>)}</div>
      </Card>
      <Card className="p-5">
        <div className="mb-4"><h2 className="font-semibold">Minecraft-чат · активность</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Уникальные игроки и сообщения по интервалам.</p></div>
        <div className="space-y-2">{chatRows.slice(-12).map((r:any,i:number)=><div key={i} className="grid grid-cols-[56px_1fr_60px] items-center gap-2 text-xs"><span className="text-[var(--muted-foreground)]">{new Date(r.bucket).toLocaleDateString("ru-RU",{day:"2-digit",month:"2-digit"})}</span><div className="space-y-1"><Bar value={Number(r.messages||0)} max={maxChat}/><p className="text-[11px] text-[var(--muted-foreground)]">{Number(r.unique_players||0)} уникальных</p></div><span className="text-right font-medium">{Number(r.messages||0)}</span></div>)}</div>
        {!chatRows.length&&<p className="py-8 text-center text-xs text-[var(--muted-foreground)]">Сообщений за период нет.</p>}
      </Card>
    </div>

    <section className="mt-5">
      <div className="mb-3"><h2 className="text-sm font-semibold">2 · Все игроки</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Общая картина сообщества.</p></div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
        {metric("Игроков",totalPlayers)}
        {metric("Активны сейчас",activePlayers)}
        {metric("Средний Rating",avgRating)}
        {metric("Средний уровень",avgLevel.toFixed(1))}
        {metric("Всего XP",totalXp.toLocaleString("ru-RU"))}
        {metric("Достижений",data.achievements)}
      </div>
    </section>

    <section className="mt-5">
      <div className="mb-3"><h2 className="text-sm font-semibold">3 · Общая игровая статистика</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Накопительные показатели всех игроков.</p></div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5">
        {metric("Убийства",totalKills)}{metric("Смерти",totalDeaths)}{metric("K/D",kd)}{metric("Блоков поставлено",totalBlocksPlaced)}{metric("Блоков сломано",totalBlocksBroken)}{metric("Мобов убито",totalMobs)}{metric("Дистанция",totalDistance)}{metric("Урон нанесён",totalDamage)}{metric("Урон получен",totalDamageTaken)}{metric("Игровое время",Math.floor(totalPlaytime/60)+" ч")}
      </div>
    </section>

    <section className="mt-5">
      <div className="mb-3"><h2 className="text-sm font-semibold">4 · Ты среди всех</h2><p className="mt-0.5 text-xs text-[var(--muted-foreground)]">Твоя позиция показывается отдельно.</p></div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Card className="prisma-glass-surface border-[var(--primary)]/35 p-5"><p className="text-xs text-[var(--muted-foreground)]">Рейтинг</p><p className="mt-2 text-3xl font-semibold">#{data.myRating??"—"}</p></Card>
        <Card className="prisma-glass-surface border-[var(--primary)]/35 p-5"><p className="text-xs text-[var(--muted-foreground)]">Убийства</p><p className="mt-2 text-3xl font-semibold">#{data.myKills??"—"}</p></Card>
      </div>
    </section>

    <div className="mt-5 grid gap-4 xl:grid-cols-2">
      <Card className="p-5"><div className="flex items-end justify-between gap-3"><div><h2 className="font-semibold">Топ по рейтингу</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Первые 8 игроков.</p></div><span className="text-xs text-[var(--muted-foreground)]">{data.myRating ? "#"+data.myRating : ""}</span></div><div className="mt-5 space-y-4">{ratingTop.map((p:any)=><Link key={p.id} href={"/app/players/"+encodeURIComponent(p.minecraft_nickname)} className={"prisma-glass-hover block rounded-xl p-2 "+(p.id===me.id?"shadow-[inset_3px_0_0_var(--primary)]":"")}><div className="mb-1 flex justify-between gap-3 text-sm"><span className="truncate font-medium">{p.minecraft_nickname}{p.id===me.id?" · Вы":""}</span><span className="shrink-0 font-semibold">{p.value}</span></div><Bar value={Number(p.value)} max={maxRating}/></Link>)}</div></Card>
      <Card className="p-5"><div className="flex items-end justify-between gap-3"><div><h2 className="font-semibold">Топ по убийствам</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Первые 8 игроков.</p></div><span className="text-xs text-[var(--muted-foreground)]">{data.myKills ? "#"+data.myKills : ""}</span></div><div className="mt-5 space-y-4">{killTop.map((p:any)=><Link key={p.id} href={"/app/players/"+encodeURIComponent(p.minecraft_nickname)} className={"prisma-glass-hover block rounded-xl p-2 "+(p.id===me.id?"shadow-[inset_3px_0_0_var(--primary)]":"")}><div className="mb-1 flex justify-between gap-3 text-sm"><span className="truncate font-medium">{p.minecraft_nickname}{p.id===me.id?" · Вы":""}</span><span className="shrink-0 font-semibold">{p.value}</span></div><Bar value={Number(p.value)} max={maxKills}/></Link>)}</div></Card>
    </div>

    {detailed && <Card className="mt-4 overflow-hidden">
      <div className="border-b p-5"><h2 className="font-semibold">Детально · мой Minecraft-чат</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Ваши сохранённые сообщения за выбранный период: когда, в каком мире и что было отправлено.</p></div>
      <div className="max-h-[560px] overflow-auto">
        <div className="space-y-2 p-3 sm:hidden">
          {myChat.map((x:any)=><article key={x.id} className="prisma-glass-surface rounded-xl border p-3">
            <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
              <span className="font-medium">{new Date(x.created_at).toLocaleString("ru-RU")}</span>
              <span className="text-[var(--muted-foreground)]">{x.world||"—"}</span>
            </div>
            <p className="mt-2 break-words text-sm">{x.message}</p>
          </article>)}
          {!myChat.length&&<p className="px-5 py-8 text-center text-xs text-[var(--muted-foreground)]">Сохранённых сообщений за период нет.</p>}
        </div>
        <table className="hidden w-full min-w-[720px] text-left text-sm sm:table"><thead className="sticky top-0 prisma-glass-surface"><tr className="border-b text-xs text-[var(--muted-foreground)]"><th className="p-3">Когда</th><th className="p-3">Мир</th><th className="p-3">Сообщение</th></tr></thead><tbody>{myChat.map((x:any)=><tr key={x.id} className="border-b align-top"><td className="whitespace-nowrap p-3 text-xs text-[var(--muted-foreground)]">{new Date(x.created_at).toLocaleString("ru-RU")}</td><td className="p-3 text-xs text-[var(--muted-foreground)]">{x.world||"—"}</td><td className="p-3">{x.message}</td></tr>)}</tbody></table>
      </div>
    </Card>}
    </div>
  );
}
