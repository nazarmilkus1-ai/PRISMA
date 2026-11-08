import { PARTICIPANT_REPORT_RPC, REPORT_STATUS_LABELS, REPORT_TYPE_LABELS } from "@prisma-eco/contracts";
import { isPublicModuleEnabled } from "@/lib/modules";
import Link from "next/link";
import {notFound} from "next/navigation";
import {Card} from "@/components/Card";
import {requireUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {Badge,CardContent,CardHeader,CardTitle,PageHeader} from "@prisma-eco/ui";

export default async function ReportPage({params}:{params:Promise<{id:string}>}){
 if(!(await isPublicModuleEnabled("reports")))notFound();
 const user=await requireUser();
 const{id}=await params;
 const db=await createSupabaseServerClient();
 const{data:payload,error}=await db.rpc(PARTICIPANT_REPORT_RPC.detail,{p_report_id:id});
 if(error||!payload||typeof payload!=="object")return notFound();
 const report=(payload as any).report;
 const history=Array.isArray((payload as any).history)?(payload as any).history:[];
 if(!report)return notFound();

 const statusLabel = REPORT_STATUS_LABELS;
 const typeLabel = REPORT_TYPE_LABELS;
 const currentStatus=REPORT_STATUS_LABELS[report.status] ?? report.status;
 const variant=report.status==="RESOLVED"?"success":report.status==="DISMISSED"?"destructive":report.status==="IN_REVIEW"?"warning":"secondary";

 return <div className="space-y-6">
  <div>
   <Link href="/app/reports" className="text-xs text-muted-foreground hover:text-foreground">← Все репорты</Link>
   <PageHeader eyebrow="Участие" title={report.ticket_no?"Репорт #"+report.ticket_no:"Репорт"} description="Подробности обращения и история его обработки." actions={<Badge variant={variant}>{currentStatus}</Badge>}/>
  </div>

  <Card>
   <CardHeader><CardTitle>Обращение</CardTitle></CardHeader>
   <CardContent className="grid gap-5 sm:grid-cols-2">
    <Field label="Тип" value={typeLabel[report.type]||String(report.type)}/>
    <Field label="Приоритет" value={report.priority||"—"}/>
    <Field label="Категория" value={report.category||"—"}/>
    <Field label="Цель" value={report.target_nickname||"—"}/>
    <Field label="Создан" value={new Date(report.created_at).toLocaleString("ru-RU")}/>
    <Field label="Обновлён" value={new Date(report.updated_at).toLocaleString("ru-RU")}/>
    {report.occurred_at?<Field label="Время события" value={new Date(report.occurred_at).toLocaleString("ru-RU")}/>:null}
    {report.resolved_at?<Field label="Решён" value={new Date(report.resolved_at).toLocaleString("ru-RU")}/>:null}
    <div className="sm:col-span-2"><p className="text-xs text-muted-foreground">Описание</p><p className="mt-2 whitespace-pre-wrap text-sm leading-7">{report.description}</p></div>
   </CardContent>
  </Card>

  <Card>
   <CardHeader><CardTitle>История статуса</CardTitle></CardHeader>
   <CardContent>
    {history?.length?<div className="space-y-3">{history.map((item:any,index:number)=><div key={item.id} className="relative pl-7"><span className="absolute left-0 top-1.5 size-2.5 rounded-full bg-[var(--primary)]"/>{index<history.length-1?<span className="absolute left-[4px] top-4 h-[calc(100%+8px)] w-px bg-[var(--border)]"/>:null}<div className="flex flex-wrap items-center justify-between gap-2"><p className="text-sm font-semibold">{item.from_status?(statusLabel[item.from_status]||item.from_status)+" → ":""}{statusLabel[item.to_status]||item.to_status}</p><time className="text-xs text-muted-foreground">{new Date(item.created_at).toLocaleString("ru-RU")}</time></div></div>)}</div>:<p className="text-sm text-muted-foreground">Изменений статуса пока нет.</p>}
   </CardContent>
  </Card>
 </div>;
}

function Field({label,value}:{label:string;value:string}){
 return <div><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 text-sm font-medium">{value}</p></div>;
}
