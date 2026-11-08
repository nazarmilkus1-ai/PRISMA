import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import {notFound, redirect} from "next/navigation";
import {requireUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {STAFF_RPC} from "@prisma-eco/contracts";
import {Card} from "@/components/Card";

export const metadata={title:"История карты"};

export default async function MapHistoryPage(){
  await requireModule("map");
  await requireUser();

  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(STAFF_RPC.mapHistory,{p_limit:100});

  if(error){
    redirect("/app/map");
  }

  const rows=Array.isArray(data)?data:[];

  return <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6">
    <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">MAP HISTORY</p>
    <h1 className="mt-2 text-4xl font-semibold">История карты</h1>
    <p className="mt-2 text-sm text-[var(--muted-foreground)]">Изменения маркеров и территориальных объектов.</p>
    <div className="mt-6 space-y-2">
      {rows.map((x:any)=><Card key={x.id} className="p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <span className="font-mono text-xs font-semibold">{x.action}</span>
          <span className="text-xs text-[var(--muted-foreground)]">{new Date(x.created_at).toLocaleString("ru-RU")}</span>
        </div>
        <pre className="mt-3 max-h-40 overflow-auto rounded-xl bg-[var(--muted)] p-3 text-[11px]">{JSON.stringify(x.snapshot,null,2)}</pre>
      </Card>)}
      {!rows.length&&<Card className="p-10 text-center text-sm text-[var(--muted-foreground)]">Изменений карты ещё не зафиксировано.</Card>}
    </div>
  </div>;
}
