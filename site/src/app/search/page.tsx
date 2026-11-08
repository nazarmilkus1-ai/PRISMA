import {requireMember} from "@/lib/member";
import {getGlobalSearch} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";
import Link from "next/link";
import { getPublicModuleAvailability } from "@/lib/modules";

export const metadata={title:"Поиск"};

export default async function SearchPage({searchParams}:{searchParams:Promise<{q?:string}>}){
 await requireMember();
 const enabledModules=await getPublicModuleAvailability();
 const q=((await searchParams).q||"").trim();
 const result=q?await getGlobalSearch(q):{players:[],clans:[],news:[],wiki:[],market:[]};
 const groups=[
  ["players","Игроки",result.players,(x:any)=>"/players/"+encodeURIComponent(x.minecraft_nickname),(x:any)=>x.minecraft_nickname],
  ["clans","Кланы",result.clans,(x:any)=>"/clans/"+x.id,(x:any)=>"["+x.tag+"] "+x.name],
  ["public-content","Новости",result.news,(x:any)=>"/news/"+x.id,(x:any)=>x.title],
  ["public-content","Wiki",result.wiki,(x:any)=>"/wiki/"+x.slug,(x:any)=>x.title],
  ["market","Рынок",result.market,()=>"/market",(x:any)=>x.title+" · "+x.kind],
 ] as const;

 return <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
  <SectionTitle eyebrow="PRISMA SEARCH" title="Глобальный поиск" description="Ищи участников, кланы, новости, Wiki и объявления в одном месте."/>
  <form action="/search" className="mt-6 flex gap-2">
   <input autoFocus name="q" defaultValue={q} placeholder="Что ищем?" className="prisma-glass-control flex-1 rounded-xl border px-4 py-3 text-sm"/>
   <button className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-3 text-sm font-semibold">Найти</button>
  </form>
  {q?<div className="mt-6 grid gap-4 lg:grid-cols-2">
   {groups.filter(([moduleId])=>enabledModules[moduleId]).map(([moduleId,label,rows,href,textFn]:any)=><Card key={moduleId+":"+label} className="overflow-hidden">
    <div className="flex items-center justify-between border-b px-5 py-4"><h2 className="font-semibold">{label}</h2><span className="text-xs text-[var(--muted-foreground)]">{rows.length}</span></div>
    <div className="divide-y">
     {rows.map((x:any)=><Link key={x.id} href={href(x)} className="block px-5 py-3 text-sm hover:bg-[var(--muted)]">{textFn(x)}</Link>)}
     {!rows.length&&<p className="px-5 py-6 text-sm text-[var(--muted-foreground)]">Ничего не найдено.</p>}
    </div>
   </Card>)}
  </div>:<Card className="mt-6 p-10 text-center text-sm text-[var(--muted-foreground)]">Введите запрос, чтобы начать поиск.</Card>}
 </div>;
}
