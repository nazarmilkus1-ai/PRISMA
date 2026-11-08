import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import { getRankingEntry, getRankings } from "@/lib/data";
import { Card } from "@/components/Card";
import { SectionTitle } from "@/components/SitePrimitives";

const cats = [
  ["rating","Rating"],["kills","Kills"],["deaths","Deaths"],["kdr","K/D"],
  ["playtime","Playtime"],["blocks","Broken"],["blocks_placed","Placed"],["damage","Damage"],["damage_taken","Taken"],["distance","Distance"],["mobs","Mobs"],["achievements","Achievements"],["activity","Activity"],["level","Level"],["xp","XP"]
] as const;

function displayValue(v:number,c:string){
  if(c==="playtime") return Math.floor(v/60)+" ч";
  if(c==="kdr") return v.toFixed(2);
  return v.toLocaleString("ru-RU");
}

export const metadata = { title: "Рейтинги" };

export default async function RankingsPage({ searchParams }: { searchParams: Promise<{ category?: string }> }) {
  const current = await requireModuleUser("players");
  const raw = (await searchParams).category || "rating";
  const category = cats.some(([id])=>id===raw) ? raw : "rating";
  const [data, currentEntry] = await Promise.all([getRankings(category, 100), getRankingEntry(current.id, category)]);

  return (
    <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <SectionTitle eyebrow="LEADERBOARD" title="Рейтинги" description="Ключевые показатели игроков PRISMA. Ваше место подсвечивается в каждой категории."/>
      <div className="mt-5 flex gap-2 overflow-x-auto pb-1">{cats.map(([id,label])=><Link key={id} href={"/app/rankings?category="+id} className={"prisma-glass-control prisma-glass-hover shrink-0 rounded-full border px-3 py-1.5 text-xs font-semibold "+(id===category?"border-[var(--primary)]/50 text-[var(--foreground)]":"text-muted-foreground")}>{label}</Link>)}</div>
      <Card className="mt-4 overflow-hidden">
        <div className="prisma-glass-surface hidden grid-cols-[56px_minmax(0,1fr)_150px] border-b px-5 py-3 text-[11px] font-semibold uppercase tracking-wide text-[var(--muted-foreground)] sm:grid"><span>#</span><span>Игрок</span><span className="text-right">Значение</span></div>
        <div className="divide-y">
          {data.map((p:any)=>{const me=p.id===current.id;return <Link key={p.id} href={"/app/players/"+encodeURIComponent(p.minecraft_nickname)} className={"prisma-glass-hover block px-4 py-4 transition sm:px-5 "+(me?"bg-transparent shadow-[inset_3px_0_0_var(--primary)]":"")}>
            <div className="grid gap-2 sm:grid-cols-[56px_minmax(0,1fr)_150px] sm:items-center"><div className="text-sm font-semibold text-[var(--muted-foreground)]">#{p.rank}</div><div className="min-w-0"><div className="flex items-center gap-2"><span className="truncate font-semibold">{p.minecraft_nickname}</span>{me&&<span className="prisma-glass-badge rounded-full border px-2 py-0.5 text-[10px] font-bold text-primary">Вы</span>}</div><p className="mt-1 text-xs text-[var(--muted-foreground)]">Уровень {p.level||1} · {p.rating||0} RR · {p.achievements||0} достиж.</p></div><div className="text-left text-lg font-bold sm:text-right">{displayValue(Number(p.value||0),category)}</div></div>
          </Link>})}
          {!data.length&&<p className="px-6 py-12 text-center text-sm text-[var(--muted-foreground)]">Данных для этого рейтинга пока нет.</p>}
          {currentEntry && !data.some((p:any)=>p.id===current.id) && (
            <>
              <div className="prisma-glass-surface border-y px-5 py-2 text-[10px] font-semibold uppercase tracking-[.16em] text-[var(--muted-foreground)]">Ваше место</div>
              <Link href={"/app/players/"+encodeURIComponent(currentEntry.minecraft_nickname)} className="prisma-glass-surface block px-4 py-4 shadow-[inset_3px_0_0_var(--primary)] sm:px-5">
                <div className="grid gap-2 sm:grid-cols-[56px_minmax(0,1fr)_150px] sm:items-center">
                  <div className="text-sm font-semibold text-[var(--primary)]">#{currentEntry.rank}</div>
                  <div className="min-w-0"><div className="flex items-center gap-2"><span className="truncate font-semibold">{currentEntry.minecraft_nickname}</span><span className="rounded-full bg-[var(--primary)] px-2 py-0.5 text-[10px] font-bold text-[var(--primary-foreground)]">Вы</span></div><p className="mt-1 text-xs text-[var(--muted-foreground)]">Уровень {currentEntry.level||1} · {currentEntry.rating||0} RR</p></div>
                  <div className="text-left text-lg font-bold sm:text-right">{displayValue(Number(currentEntry.value||0),category)}</div>
                </div>
              </Link>
            </>
          )}
        </div>
      </Card>
    </div>
  );
}
