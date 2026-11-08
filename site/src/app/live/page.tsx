import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { STAFF_LIVE_RPC } from "@prisma-eco/contracts";
import {notFound, redirect} from "next/navigation";
import {requireUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";

export const metadata={title:"Live Feed"};

export default async function LivePage(){
  await requireModule("events");
  const user=await requireUser();
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(STAFF_LIVE_RPC.events,{p_limit:100});
  if(error)return redirect("/app/server");
  const events=Array.isArray(data)?data:[];

  return <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
    <SectionTitle eyebrow="LIVE FEED" title="События сервера" description="Служебная лента Minecraft-событий PRISMA."/>
    {error?<Card className="mt-6 p-8 text-center text-sm text-red-400">Не удалось загрузить ленту событий.</Card>:<div className="mt-6 space-y-2">
      {events.map((e:any)=><Card key={e.id} className="p-4">
        <div className="flex flex-wrap items-center gap-2">
          <span className="rounded-full bg-[var(--muted)] px-2 py-1 font-mono text-[10px] font-semibold">{e.event_type}</span>
          {e.nickname&&<span className="text-sm font-semibold">{e.nickname}</span>}
          <span className="ml-auto text-xs text-[var(--muted-foreground)]">{new Date(e.created_at).toLocaleString("ru-RU")}</span>
        </div>
        {e.message&&<p className="mt-2 whitespace-pre-wrap text-sm text-[var(--muted-foreground)]">{e.message}</p>}
        {e.command&&<p className="mt-2 break-all font-mono text-xs text-[var(--muted-foreground)]">{e.command}</p>}
        {e.world&&<p className="mt-1 text-[11px] text-[var(--muted-foreground)]">Мир: {e.world}</p>}
      </Card>)}
      {!events.length&&<Card className="p-10 text-center text-sm text-[var(--muted-foreground)]">Событий пока нет.</Card>}
    </div>}
  </div>;
}
