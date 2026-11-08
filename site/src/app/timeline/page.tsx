import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import {getTimeline} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";
export const metadata={title:"Timeline"};
export default async function TimelinePage(){
  await requireModuleMember("analytics");const items=await getTimeline();return <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6"><SectionTitle eyebrow="PRISMA TIMELINE" title="Історія подій" description="Журнал важливих змін, кланових подій, івентів та розвитку PRISMA."/><div className="mt-8 space-y-3">{items.map((x:any)=><Card key={x.id} className="p-5"><div className="flex gap-4"><div className="mt-1 flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--primary)] text-xs font-bold text-[var(--primary-foreground)]">P</div><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><p className="font-semibold">{x.title}</p><span className="rounded-full border px-2 py-0.5 text-[10px] font-semibold">{x.kind}</span></div><p className="mt-1 text-sm leading-6 text-[var(--muted-foreground)]">{x.body||"Подія PRISMA"}</p><p className="mt-2 text-xs text-[var(--muted-foreground)]">{new Date(x.occurred_at).toLocaleString("uk-UA")} {x.users?.minecraft_nickname?"· "+x.users.minecraft_nickname:""}</p></div></div></Card>)}</div></div>}
