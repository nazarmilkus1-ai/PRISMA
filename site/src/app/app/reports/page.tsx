import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { PARTICIPANT_REPORT_RPC } from "@prisma-eco/contracts";
import { notFound } from "next/navigation";
import Link from "next/link";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {Badge,Button,Card,CardContent,CardHeader,CardTitle,EmptyState,FormField,Input,PageHeader,Select,SelectTrigger,SelectValue,SelectContent,SelectItem,Table,TableBody,TableCell,TableHead,TableHeader,TableRow,Textarea} from "@prisma-eco/ui";
import { MinecraftNicknameAutocomplete } from "@/components/MinecraftNicknameAutocomplete";

export const metadata={title:"Репорты"};

export default async function ReportsPage({searchParams}:{searchParams:Promise<{error?:string;created?:string}>}){
 const user=await requireModuleUser("reports");
 const sp=await searchParams;
 const db=await createSupabaseServerClient();
 const {data:reportsPayload,error}=await db.rpc(PARTICIPANT_REPORT_RPC.list,{p_limit:50});
 if(error)throw new Error("Не удалось загрузить репорты.");
 const reports=Array.isArray(reportsPayload)?reportsPayload:[];

 return <div className="space-y-6">
  <PageHeader eyebrow="Участие" title="Репорты" description="Заявки на рассмотрение модерацией PRISMA."/>
  {sp.error?<p role="alert" className="prisma-glass-surface rounded-xl border border-destructive/30 px-3 py-2 text-sm text-destructive">{decodeURIComponent(sp.error)}</p>:null}
  {sp.created?<p className="prisma-glass-surface rounded-xl border border-emerald-500/30 px-3 py-2 text-sm text-emerald-700 dark:text-emerald-300">Репорт отправлен.</p>:null}

  <Card>
   <CardHeader><CardTitle>Создать репорт</CardTitle></CardHeader>
   <CardContent><form action="/api/reports" method="post" className="grid gap-5 md:grid-cols-2">
    <FormField label="Тип" required>
      <Select name="type" defaultValue="PLAYER">
       <SelectTrigger className="w-full"><SelectValue placeholder="Выберите тип" /></SelectTrigger>
       <SelectContent className="prisma-glass-surface min-w-[14rem] rounded-xl border text-foreground shadow-2xl">
        <SelectItem value="PLAYER" className="rounded-lg py-2.5">Игрок</SelectItem>
        <SelectItem value="BUG" className="rounded-lg py-2.5">Ошибка</SelectItem>
        <SelectItem value="SERVER" className="rounded-lg py-2.5">Проблема сервера</SelectItem>
       </SelectContent>
      </Select>
    </FormField>
    <FormField label="Minecraft-ник" description="Только для репорта на игрока."><MinecraftNicknameAutocomplete name="target_nickname" maxLength={32} placeholder="Например, Steve" autoComplete="off"/></FormField>
    <div className="md:col-span-2"><FormField label="Описание" required description="Минимум 3 символа, максимум 4000."><Textarea name="description" required minLength={3} maxLength={4000} placeholder="Опишите ситуацию как можно конкретнее."/></FormField></div>
    <div className="md:col-span-2 flex justify-end"><Button type="submit" disabled={user.is_banned}>Отправить репорт</Button></div>
   </form></CardContent>
  </Card>

  <Card className="overflow-hidden">
   <CardHeader><CardTitle>Мои репорты</CardTitle></CardHeader>
   {reports?.length?<Table><TableHeader><TableRow><TableHead>№</TableHead><TableHead>Тип</TableHead><TableHead>Цель</TableHead><TableHead>Статус</TableHead><TableHead>Создан</TableHead><TableHead /></TableRow></TableHeader><TableBody>{reports.map((r:any)=><TableRow key={r.id}><TableCell className="font-mono text-xs text-muted-foreground">{r.ticket_no?("#"+r.ticket_no):r.id.slice(0,8)}</TableCell><TableCell>{r.type==="PLAYER"?"Игрок":r.type==="BUG"?"Ошибка":"Сервер"}</TableCell><TableCell>{r.target_nickname||"—"}</TableCell><TableCell><Badge variant={r.status==="RESOLVED"?"success":r.status==="DISMISSED"?"destructive":r.status==="IN_REVIEW"?"warning":"secondary"}>{r.status==="RESOLVED"?"Решён":r.status==="DISMISSED"?"Отклонён":r.status==="IN_REVIEW"?"В работе":"Открыт"}</Badge></TableCell><TableCell className="text-xs text-muted-foreground">{new Date(r.created_at).toLocaleString("ru-RU")}</TableCell><TableCell><Link href={"/app/reports/"+r.id} className="text-xs font-medium underline underline-offset-4">Открыть</Link></TableCell></TableRow>)}</TableBody></Table>:<EmptyState icon="flag" title="Репортов пока нет" description="Создайте первое обращение, когда понадобится помощь модерации."/>}
  </Card>
 </div>;
}
