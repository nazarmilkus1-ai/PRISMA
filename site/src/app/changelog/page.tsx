import {getPublicNews} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";
export const metadata={title:"Changelog"};
export default async function ChangelogPage(){const all=await getPublicNews(100);const items=all.filter((x:any)=>x.kind==="UPDATE");return <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6"><SectionTitle eyebrow="CHANGELOG" title="Изменения PRISMA" description="Версии, улучшения, новые системы и важные технические изменения."/><div className="mt-6 space-y-3">{items.map((x:any)=><Card key={x.id} className="p-5"><div className="flex items-center justify-between gap-3"><h2 className="font-semibold">{x.title}</h2><span className="text-xs text-[var(--muted-foreground)]">{new Date(x.published_at||x.created_at).toLocaleDateString("ru-RU")}</span></div><p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-[var(--muted-foreground)]">{x.body}</p></Card>)}</div></div>}
