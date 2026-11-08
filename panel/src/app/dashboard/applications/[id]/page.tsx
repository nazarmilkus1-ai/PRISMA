import { formatDateTime } from "@prisma-eco/shared";
import Link from "next/link";
import {notFound} from "next/navigation";
import {requireAdmin} from "@/lib/require-admin";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {Badge,Card,CardContent,CardHeader,CardTitle,PageHeader} from "@prisma-eco/ui";
import {ApplicationReview} from "./ApplicationReview";
import { STAFF_RPC } from "@prisma-eco/contracts";

type ApplicationHistoryEntry = {
  id: string | number;
  action: string;
  actor_tg_id: number | null;
  reason: string | null;
  created_at: string;
};
type ApplicationDetail = {
  id: string;
  application_no: number | null;
  nickname: string;
  full_name: string;
  age: number;
  birth_date: string | null;
  platform: string;
  discovery_source: string | null;
  goal: string | null;
  about: string | null;
  rejection_reason: string | null;
  status: "PENDING" | "ACCEPTED" | "REJECTED" | string;
  history?: ApplicationHistoryEntry[];
};

export default async function ApplicationDetailPage({params}:{params:Promise<{id:string}>}){
 const admin=await requireAdmin("application.view");if(!admin)return null;const {id}=await params;const db=await createSupabaseServerClient();
 const {data,error}=await db.rpc(STAFF_RPC.application,{p_application_id:id});
 const application=(data??null) as ApplicationDetail | null;
 const history=application?.history ?? [];
 if(error)throw new Error("Не удалось загрузить заявку.");if(!application)notFound();
 const label=application.status==="PENDING"?"На рассмотрении":application.status==="ACCEPTED"?"Принята":"Отклонена";
 return <div className="space-y-6">
  <PageHeader eyebrow={"Заявка #"+application.application_no} title={application.nickname} description={application.full_name} actions={<Link href="/dashboard/applications" className="text-sm text-muted-foreground hover:text-foreground">← Все заявки</Link>}/>
  <div className="grid gap-4 xl:grid-cols-[1fr_360px]">
   <Card><CardHeader className="flex-row items-center justify-between gap-4"><CardTitle>Данные заявки</CardTitle><Badge variant={application.status==="ACCEPTED"?"success":application.status==="REJECTED"?"destructive":"warning"}>{label}</Badge></CardHeader><CardContent className="grid gap-5 sm:grid-cols-2">
    <Field label="Имя" value={application.full_name}/><Field label="Возраст" value={String(application.age)}/><Field label="Дата рождения" value={application.birth_date||"—"}/><Field label="Minecraft" value={application.nickname}/><Field label="Платформа" value={application.platform}/><Field label="Источник" value={application.discovery_source||"—"}/><Field label="Цель" value={application.goal||"—"} wide/><Field label="О себе" value={application.about||"—"} wide/>
    {application.rejection_reason?<div className="sm:col-span-2 rounded-md border border-destructive/30 bg-destructive/5 p-3"><p className="text-xs font-medium text-destructive">Причина отклонения</p><p className="mt-1 text-sm whitespace-pre-wrap">{application.rejection_reason}</p></div>:null}
   </CardContent></Card>
   <div className="space-y-4"><ApplicationReview applicationId={application.id} status={application.status}/><Card><CardHeader><CardTitle>История</CardTitle></CardHeader><CardContent className="space-y-4">{(history||[]).map((h)=><div key={h.id} className="border-l-2 pl-3"><p className="text-sm font-medium">{h.action}</p><p className="mt-0.5 text-xs text-muted-foreground">{h.actor_tg_id?"Telegram "+h.actor_tg_id:"Система"} · {formatDateTime(h.created_at)}</p>{h.reason?<p className="mt-1 text-xs text-muted-foreground whitespace-pre-wrap">{h.reason}</p>:null}</div>)}{!history?.length?<p className="text-sm text-muted-foreground">История пуста.</p>:null}</CardContent></Card></div>
  </div>
 </div>;
}
function Field({label,value,wide=false}:{label:string;value:string;wide?:boolean}){return <div className={wide?"sm:col-span-2":""}><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 whitespace-pre-wrap text-sm leading-6">{value}</p></div>}
