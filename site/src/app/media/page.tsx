import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import {getMedia} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";
export const metadata={title:"Медиа"};
export default async function MediaPage(){
  await requireModule("public-content");const media=await getMedia();return <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6"><SectionTitle eyebrow="MEDIA" title="Медиа PRISMA" description="Скриншоты, видео и другие материалы сообщества."/><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{media.map((m:any)=><a key={m.id} href={m.url} target="_blank" rel="noreferrer"><Card className="overflow-hidden prisma-glass-hover"><div className="flex aspect-video items-center justify-center bg-[var(--muted)] text-3xl">{m.kind==="VIDEO"?"▶":"▧"}</div><div className="p-5"><h2 className="font-semibold">{m.title}</h2><p className="mt-1 text-sm text-[var(--muted-foreground)]">{m.description||"Материал PRISMA"}</p></div></Card></a>)}</div></div>}
