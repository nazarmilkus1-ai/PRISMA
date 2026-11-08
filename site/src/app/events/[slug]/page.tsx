import {notFound} from "next/navigation";
import { requireModule } from "@/lib/access";
import { isPublicModuleEnabled } from "@/lib/modules";
import Link from "next/link";
import {Badge,Card,CardContent,CardHeader,CardTitle,Table,TableBody,TableCell,TableHead,TableHeader,TableRow} from "@prisma-eco/ui";
import {PUBLIC_RPC} from "@prisma-eco/contracts";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {getCurrentUser} from "@/lib/auth";

export async function generateMetadata({params}:{params:Promise<{slug:string}>}){
  if(!(await isPublicModuleEnabled("events")))return{title:"Событие не найдено"};
  const{slug}=await params;
  const db=await createSupabaseServerClient();
  const{data}=await db.rpc(PUBLIC_RPC.eventDetails,{p_slug:slug});
  return{title:data&&typeof data==="object"&&(data as any).event?.title?String((data as any).event.title):"Событие"};
}

const errorLabel: Record<string,string> = {
  forbidden: "Регистрация доступна только одобренным участникам с whitelist.",
  invalid: "Некорректные параметры регистрации.",
  USER_NOT_LINKED: "Профиль PRISMA не связан с текущим аккаунтом.",
  EVENT_NOT_FOUND: "Событие не найдено.",
  EVENT_NOT_OPEN: "Регистрация на это событие закрыта.",
  REGISTRATION_CLOSED: "Регистрация уже закрыта.",
  EVENT_FULL: "Свободных мест больше нет.",
  REGISTRATION_NOT_FOUND: "Вы не зарегистрированы на это событие.",
  EVENT_ALREADY_STARTED: "Отменить регистрацию после начала события нельзя.",
};

export default async function EventPage({
  params,searchParams,
}:{
  params:Promise<{slug:string}>;
  searchParams:Promise<{updated?:string;error?:string}>;
}){
  await requireModule("events");
  const{slug}=await params;
  const sp=await searchParams;
  const db=await createSupabaseServerClient();
  const[{data,error},user]=await Promise.all([
    db.rpc(PUBLIC_RPC.eventDetails,{p_slug:slug}),
    getCurrentUser(),
  ]);
  if(error||!data||typeof data!=="object"||!(data as any).event)return notFound();

  const event=(data as any).event;
  const participants=Array.isArray((data as any).participants)?(data as any).participants:[];
  const registrationOpen=event.registration_open===true;
  const registered=event.registered===true;
  const canRegister=Boolean(user&&user.status==="ACCEPTED"&&!user.is_banned&&user.is_whitelisted);
  const statusText=event.status==="live"?"Идёт сейчас":event.status==="finished"?"Завершено":event.status==="scheduled"?"Запланировано":"Опубликовано";

  return(
    <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6">
      <Link href="/events" className="prisma-glass-control prisma-glass-hover inline-flex rounded-lg border px-3 py-1.5 text-xs text-muted-foreground">← Все события</Link>

      {sp.updated?<Card className="mt-4 border-primary/30 bg-primary/5 p-4 text-sm">Регистрация обновлена.</Card>:null}
      {sp.error?<Card className="mt-4 border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">{errorLabel[sp.error]||sp.error}</Card>:null}

      <div className="mt-4 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-xs font-medium uppercase tracking-[0.16em] text-muted-foreground">PRISMA EVENT</p>
          <h1 className="mt-2 text-4xl font-semibold tracking-tight">{event.title}</h1>
        </div>
        <Badge variant={event.status==="live"?"success":event.status==="finished"?"secondary":"warning"}>{statusText}</Badge>
      </div>

      <div className="mt-5 flex flex-wrap items-center gap-3">
        <p className="max-w-3xl text-sm leading-7 text-muted-foreground">{event.description}</p>
        {canRegister&&registrationOpen?(
          <form action="/api/events/register" method="post" className="shrink-0">
            <input type="hidden" name="event_id" value={event.id}/>
            <input type="hidden" name="slug" value={slug}/>
            <input type="hidden" name="action" value={registered?"unregister":"register"}/>
            <button className={registered?"prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-semibold":"rounded-xl bg-[var(--primary)] px-4 py-2.5 text-sm font-semibold text-[var(--primary-foreground)]"}>
              {registered?"Отменить регистрацию":"Зарегистрироваться"}
            </button>
          </form>
        ):null}
      </div>

      {!user?<p className="mt-3 text-xs text-muted-foreground">Для регистрации войдите в аккаунт PRISMA.</p>:null}
      {user&&!canRegister?<p className="mt-3 text-xs text-muted-foreground">Регистрация доступна одобренным участникам с whitelist.</p>:null}
      {canRegister&&!registrationOpen?<p className="mt-3 text-xs text-muted-foreground">Регистрация на это событие закрыта.</p>:null}

      <div className="mt-6 grid gap-3 sm:grid-cols-3">
        <InfoCard label="Начало" value={event.starts_at?new Date(event.starts_at).toLocaleString("ru-RU"):"—"}/>
        <InfoCard label="Участники" value={event.max_participants?participants.length+" / "+event.max_participants:String(participants.length)}/>
        <InfoCard label="Награды" value={event.reward_config?.title||event.reward_config?.description||"По регламенту события"}/>
      </div>

      <Card className="mt-6 overflow-hidden">
        <CardHeader><CardTitle>Результаты</CardTitle></CardHeader>
        {participants.length?(
          <Table>
            <TableHeader><TableRow><TableHead>Место</TableHead><TableHead>Игрок</TableHead><TableHead className="text-right">Результат</TableHead></TableRow></TableHeader>
            <TableBody>{participants.map((participant:any,index:number)=>(
              <TableRow key={participant.minecraft_nickname+":"+index}>
                <TableCell className="font-medium">#{participant.placement||index+1}</TableCell>
                <TableCell>{participant.minecraft_nickname||"Игрок"}</TableCell>
                <TableCell className="text-right font-medium">{participant.score??"—"}</TableCell>
              </TableRow>
            ))}</TableBody>
          </Table>
        ):(
          <CardContent><p className="text-sm text-muted-foreground">Результаты появятся после события.</p></CardContent>
        )}
      </Card>
    </div>
  );
}

function InfoCard({label,value}:{label:string;value:string}){
  return <Card className="p-5"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 text-sm font-medium">{value}</p></Card>;
}
