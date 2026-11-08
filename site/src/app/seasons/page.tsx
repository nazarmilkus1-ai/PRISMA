import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { SEASON_STATUS_LABELS } from "@prisma-eco/contracts";
import { notFound } from "next/navigation";
import Link from "next/link";
import {getSeasons} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";
export const metadata={title:"Сезоны"};
export default async function SeasonsPage(){
  await requireModuleMember("public-content");const seasons=await getSeasons();return <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6"><SectionTitle eyebrow="SEASONS" title="Сезоны" description="Сезонные рейтинги, результаты и архив PRISMA."/><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{seasons.map((s:any)=><Link key={s.id} href={"/seasons/"+s.slug}><Card className="p-5 transition hover:-translate-y-0.5 prisma-glass-hover"><div className="flex items-center justify-between"><span className="rounded-full border px-2.5 py-1 text-xs font-semibold">{SEASON_STATUS_LABELS[s.status] ?? s.status}</span><span className="text-xs text-[var(--muted-foreground)]">{s.starts_at?new Date(s.starts_at).toLocaleDateString("ru-RU"):"—"}</span></div><h2 className="mt-4 text-lg font-semibold">{s.name}</h2><p className="mt-1 text-sm text-[var(--muted-foreground)]">{s.ends_at?"до "+new Date(s.ends_at).toLocaleDateString("ru-RU"):"Без даты завершения"}</p></Card></Link>)}{!seasons.length&&<Card className="p-8 text-center text-sm text-[var(--muted-foreground)]">Сезонов ещё нет.</Card>}</div></div>}
