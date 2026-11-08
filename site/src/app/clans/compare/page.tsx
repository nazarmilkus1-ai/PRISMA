import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import {getPublicClans,getClanPage} from "@/lib/data";
import {Card} from "@/components/Card";
export const metadata={title:"Clan VS Clan"};
export default async function ClanComparePage({searchParams}:{searchParams:Promise<{a?:string;b?:string}>}){
  await requireModuleMember("clans");
  const sp=await searchParams;
  const clans=await getPublicClans(200);
  const a=clans.find((x:any)=>x.id===sp.a)||clans[0];
  const b=clans.find((x:any)=>x.id===sp.b&&x.id!==a?.id)||clans.find((x:any)=>x.id!==a?.id)||clans[1];
  const aPage=a?await getClanPage(a.id):null;
  const wars=aPage?.wars?.filter((w:any)=>b&&String(w.opponent_tag||"").toLowerCase()===String(b.tag||"").toLowerCase())||[];
  if(!a||!b)return <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6"><Card className="p-8 text-center">Недостаточно кланов для сравнения.</Card></div>;
  return <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
    <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">CLAN VS CLAN</p><h1 className="mt-2 text-4xl font-semibold">Сравнение кланов</h1>
    <form className="mt-6 grid gap-3 md:grid-cols-[1fr_1fr_auto]">
      <select name="a" defaultValue={a.id} className="prisma-glass-control rounded-xl border px-3 py-3 text-sm">{clans.map((c:any)=><option key={c.id} value={c.id}>[{c.tag}] {c.name}</option>)}</select>
      <select name="b" defaultValue={b.id} className="prisma-glass-control rounded-xl border px-3 py-3 text-sm">{clans.map((c:any)=><option key={c.id} value={c.id}>[{c.tag}] {c.name}</option>)}</select>
      <button className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-3 text-sm font-semibold">Сравнить</button>
    </form>
    <div className="mt-6 grid gap-4 md:grid-cols-2">{[a,b].map((c:any)=><Card key={c.id} className="p-6"><p className="text-xs text-[var(--muted-foreground)]">[{c.tag}]</p><h2 className="mt-1 text-2xl font-semibold">{c.name}</h2><div className="mt-5 grid grid-cols-2 gap-3">{[["Очки",c.points??0],["Rating",c.rating],["Level",c.level],["W",c.wins],["L",c.losses],["XP",c.xp]].map(([k,v])=><div key={String(k)} className="prisma-glass-surface rounded-xl border p-3"><p className="text-xs text-[var(--muted-foreground)]">{k}</p><p className="mt-1 font-semibold">{v}</p></div>)}</div></Card>)}</div>
    <Card className="mt-6 overflow-hidden"><div className="border-b px-5 py-4"><h2 className="font-semibold">Личные встречи</h2></div><div className="divide-y">{wars.map((w:any)=><div key={w.id} className="prisma-glass-hover flex flex-wrap items-center justify-between gap-3 px-5 py-4"><span className="text-sm">{w.status}</span><b>{w.score_for} : {w.score_against}</b></div>)}{!wars.length&&<p className="p-8 text-sm text-[var(--muted-foreground)]">Зафиксированных войн между этими кланами ещё нет.</p>}</div></Card>
    <div className="mt-4"><Link href="/clans" className="prisma-glass-control prisma-glass-hover inline-flex rounded-lg border px-3 py-1.5 text-sm">← К кланам</Link></div>
  </div>;
}
