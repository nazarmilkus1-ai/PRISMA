import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { PARTICIPANT_READ_RPC } from "@prisma-eco/contracts";
import Link from "next/link";
import { notFound } from "next/navigation";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {Badge,Card,CardContent,CardHeader,CardTitle,PageHeader} from "@prisma-eco/ui";
import {ApplicationForm} from "./ApplicationForm";

export const metadata={title:"Моя заявка"};

export default async function ApplicationPage({searchParams}:{searchParams:Promise<{error?:string;submitted?:string}>}){
 const user=await requireModuleUser("applications");
 const sp=await searchParams;
 const db=await createSupabaseServerClient();
 const {data:applicationPayload,error:applicationError}=await db.rpc(PARTICIPANT_READ_RPC.application);
 if(applicationError)throw new Error("Не удалось загрузить заявку.");
 const application=applicationPayload&&typeof applicationPayload==="object"?applicationPayload as any:null;
 if(application){
  const label=application.status==="ACCEPTED"?"Принята":application.status==="REJECTED"?"Отклонена":"На рассмотрении";
  const cooldownActive=application.status==="REJECTED"&&application.cooldown_until&&new Date(application.cooldown_until).getTime()>Date.now();
  const canResubmit=application.status==="REJECTED"&&!cooldownActive;
  return <div className="space-y-6">
   <PageHeader eyebrow="Участие" title="Моя заявка" description="Статус последней заявки и данные, отправленные администрации." actions={application.status==="ACCEPTED"?<Link href="/app" className="prisma-glass-primary prisma-glass-hover inline-flex h-9 items-center rounded-md border px-3.5 text-sm font-medium text-primary">Открыть кабинет</Link>:null}/>
   {sp.error?<p role="alert" className="prisma-glass-surface rounded-xl border border-destructive/30 px-3 py-2 text-sm text-destructive">{sp.error}</p>:null}
   {sp.submitted?<p className="prisma-glass-surface rounded-xl border border-emerald-500/30 px-3 py-2 text-sm text-emerald-700 dark:text-emerald-300">Новая заявка отправлена и ожидает рассмотрения.</p>:null}
   <Card><CardHeader className="flex-row items-center justify-between gap-4"><div><CardTitle>Заявка #{application.application_no}</CardTitle><p className="mt-1 text-xs text-muted-foreground">{new Date(application.created_at).toLocaleString("ru-RU")}</p></div><Badge variant={application.status==="ACCEPTED"?"success":application.status==="REJECTED"?"destructive":"warning"}>{label}</Badge></CardHeader>
    <CardContent className="grid gap-5 sm:grid-cols-2">
     <Field label="Имя" value={application.full_name}/><Field label="Возраст" value={String(application.age)}/><Field label="Дата рождения" value={application.birth_date||"—"}/><Field label="Minecraft" value={application.nickname}/><Field label="Платформа" value={application.platform}/><Field label="Источник" value={application.discovery_source||"—"}/><Field label="Цель" value={application.goal||"—"} wide/><Field label="О себе" value={application.about||"—"} wide/>
     {application.rejection_reason?<div className="prisma-glass-surface sm:col-span-2 rounded-xl border border-destructive/30 p-3"><p className="text-xs font-medium text-destructive">Причина отклонения</p><p className="mt-1 text-sm">{application.rejection_reason}</p></div>:null}
    </CardContent>
   </Card>

   {application.status==="REJECTED"&&!canResubmit&&<Card><CardContent><p className="text-sm">Повторная подача пока недоступна.</p>{application.cooldown_until?<p className="mt-1 text-xs text-muted-foreground">До {new Date(application.cooldown_until).toLocaleString("ru-RU")}</p>:null}</CardContent></Card>}

   {canResubmit?<div className="space-y-4">
     <PageHeader eyebrow="Повторная подача" title="Подать заявку снова" description="Предыдущие данные уже подставлены. Их можно изменить перед отправкой."/>
     <ApplicationForm defaults={{fullName:application.full_name||user.full_name||"",birthDate:application.birth_date||user.birth_date||"",nickname:application.nickname?.replace(/^\./,"")||user.minecraft_nickname?.replace(/^\./,"")||"",platform:application.platform||user.platform||"JAVA",goal:application.goal||"",about:application.about||"",discoverySource:application.discovery_source||""}}/>
   </div>:null}
  </div>;
 }
 if(user.status==="ACCEPTED")return <Card><CardContent><p className="text-sm">У вас уже есть доступ к PRISMA. Новая заявка не требуется.</p></CardContent></Card>;

 return <div className="space-y-6">
  <PageHeader eyebrow="Вступление" title="Заявка в PRISMA" description="Та же модель заявки используется Telegram-ботом и сайтом."/>
  {sp.error?<p role="alert" className="prisma-glass-surface rounded-xl border border-destructive/30 px-3 py-2 text-sm text-destructive">{sp.error}</p>:null}
  {sp.submitted?<p className="prisma-glass-surface rounded-xl border border-emerald-500/30 px-3 py-2 text-sm text-emerald-700 dark:text-emerald-300">Заявка отправлена и ожидает рассмотрения.</p>:null}
  <ApplicationForm defaults={{fullName:user.full_name||[user.first_name,user.last_name].filter(Boolean).join(" "),birthDate:user.birth_date||"",nickname:user.minecraft_nickname?.replace(/^\./,"")||"",platform:user.platform||"JAVA"}}/>
 </div>;
}
function Field({label,value,wide=false}:{label:string;value:string;wide?:boolean}){return <div className={wide?"sm:col-span-2":""}><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 whitespace-pre-wrap text-sm leading-6">{value}</p></div>}
