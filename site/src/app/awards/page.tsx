import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import {getAwards} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";
export const metadata={title:"Awards"};
export default async function AwardsPage(){
  await requireModule("public-content");const awards=await getAwards();return <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6"><SectionTitle eyebrow="HALL OF FAME" title="PRISMA Awards" description="Награды за сезоны, события и достижения игроков и кланов."/><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{awards.map((a:any)=><Card key={a.id} className="p-5"><span className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">{a.kind}</span><h2 className="mt-2 text-lg font-semibold">{a.name}</h2><p className="mt-2 text-sm leading-6 text-[var(--muted-foreground)]">{a.description||"Нагорода PRISMA"}</p><p className="mt-4 text-xs text-[var(--muted-foreground)]">{a.target_type}</p></Card>)}</div>{!awards.length&&<Card className="mt-6 p-8 text-center text-sm text-[var(--muted-foreground)]">Наград пока нет.</Card>}</div>}
