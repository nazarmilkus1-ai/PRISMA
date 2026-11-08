import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { EVENT_STATUS_LABELS } from "@prisma-eco/contracts";
import { notFound } from "next/navigation";
import Link from "next/link";
import {getParticipantCalendar} from "@/lib/data";
import {Badge,Card,CardContent,CardDescription,CardHeader,CardTitle,EmptyState,PageHeader} from "@prisma-eco/ui";

export const metadata={title:"Календарь"};

export default async function ParticipantCalendarPage(){
  await requireModuleUser("events");
 const events=await getParticipantCalendar();
 const now=Date.now();
 const upcoming=events.filter((e:any)=>!e.starts_at||new Date(e.starts_at).getTime()>=now);
 const registered=upcoming.filter((e:any)=>e.registered);
 const past=events.filter((e:any)=>e.starts_at&&new Date(e.starts_at).getTime()<now);

 return <div className="space-y-6">
  <PageHeader eyebrow="Сообщество" title="Календарь событий" description="Ближайшие активности PRISMA и ваша регистрация на них." actions={<Link href="/events" className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm">Все события →</Link>}/>

  <div className="grid gap-3 sm:grid-cols-3">
   <Metric label="Ближайшие" value={upcoming.length}/>
   <Metric label="Вы зарегистрированы" value={registered.length}/>
   <Metric label="Прошедшие" value={past.length}/>
  </div>

  <Card>
   <CardHeader><CardTitle>Ближайшие события</CardTitle><CardDescription>Сначала события, на которые вы уже записались.</CardDescription></CardHeader>
   <div className="divide-y">
    {[...registered,...upcoming.filter((e:any)=>!e.registered)].slice(0,30).map((event:any)=><Link key={event.id} href={"/events/"+event.slug} className="prisma-glass-hover block px-5 py-4 transition-colors">
      <div className="flex flex-wrap items-start justify-between gap-3">
       <div><p className="text-sm font-semibold">{event.title}</p><p className="mt-1 text-xs text-muted-foreground">{event.starts_at?new Date(event.starts_at).toLocaleString("ru-RU"):"Дата уточняется"}</p></div>
       <div className="flex items-center gap-2"><Badge variant={event.registered?"success":event.status==="live"?"warning":"secondary"}>{event.registered?"Вы зарегистрированы":EVENT_STATUS_LABELS[event.status] ?? event.status}</Badge>{event.max_participants?<span className="text-xs text-muted-foreground">до {event.max_participants}</span>:null}</div>
      </div>
    </Link>)}
    {!upcoming.length?<CardContent><EmptyState icon="calendar" title="Ближайших событий нет" description="Когда администрация добавит новую активность, она появится здесь." /></CardContent>:null}
   </div>
  </Card>

  {past.length?<Card>
   <CardHeader><CardTitle>Прошедшие события</CardTitle><CardDescription>Ваши результаты остаются доступны на странице события.</CardDescription></CardHeader>
   <div className="divide-y">
    {past.slice(0,20).map((event:any)=><Link key={event.id} href={"/events/"+event.slug} className="prisma-glass-hover flex flex-wrap items-center justify-between gap-3 px-5 py-3 transition-colors">
      <div><p className="text-sm font-medium">{event.title}</p><p className="mt-1 text-xs text-muted-foreground">{event.starts_at?new Date(event.starts_at).toLocaleString("ru-RU"):"Дата уточняется"}</p></div>
      {event.my_result?.placement?<span className="text-xs font-semibold">Место #{event.my_result.placement}</span>:event.registered?<span className="text-xs text-muted-foreground">Участие</span>:null}
    </Link>)}
   </div>
  </Card>:null}
 </div>;
}

function Metric({label,value}:{label:string;value:number}){return <Card className="p-5"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 text-2xl font-semibold">{value}</p></Card>}
