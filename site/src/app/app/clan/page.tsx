import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import Link from "next/link";
import { notFound } from "next/navigation";
import {Card} from "@/components/Card";
import {getDashboardData,getParticipantClans,getClanPage} from "@/lib/data";

export const metadata={title:"Кланы"};

const roleLabel:Record<string,string>={
 owner:"Владелец",
 co_owner:"Совладелец",
 officer:"Офицер",
 member:"Участник",
 recruit:"Рекрут",
};

export default async function ClansPage({
 searchParams,
}:{searchParams:Promise<{error?:string;created?:string}>}){
 const user=await requireModuleUser("clans");
 const sp=await searchParams;
 const[{clan:myClan,membership:myMembership,invitations,clanInvites},clans,myClanDetails]=await Promise.all([
  getDashboardData(),
  getParticipantClans(100),
  user.clan_id?getClanPage(user.clan_id):Promise.resolve(null),
 ]);
 const myVillages=Array.isArray(myClanDetails?.villages)?myClanDetails.villages:[];
 const myAnnouncements=Array.isArray(myClanDetails?.announcements)?myClanDetails.announcements:[];
 const warItems=Array.isArray(myClanDetails?.wars)?myClanDetails.wars:[];
 const pendingWars=warItems.filter((w:any)=>String(w.status)==="pending");
 const activeWars=warItems.filter((w:any)=>["scheduled","active"].includes(String(w.status)));

 const sorted=[...clans].sort(
  (a:any,b:any)=>Number(b.id===user.clan_id)-Number(a.id===user.clan_id)||Number(b.rating||0)-Number(a.rating||0),
 );
 const myRole=String(myMembership?.role||"").toLowerCase();
 const canManage=["owner","officer"].includes(myRole);
 const canRoleManage=["owner","co_owner","officer"].includes(myRole);
 const isOwner=myRole==="owner";
 const roleOptions:Record<string,string[]>={
  owner:["co_owner","officer","member","recruit"],
  co_owner:["officer","member","recruit"],
  officer:["member","recruit"],
 };
 const manageableRoles=roleOptions[myRole]||[];
 const selectableClans=sorted.filter((c:any)=>c.id!==user.clan_id);
 const incomingInvites=Array.isArray(clanInvites?.incoming)?clanInvites.incoming:(invitations||[]);
 const outgoingInvites=Array.isArray(clanInvites?.outgoing)?clanInvites.outgoing:[];

 return(
  <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
   <div className="flex flex-wrap items-end justify-between gap-4">
    <div>
     <p className="text-xs font-semibold uppercase tracking-[.18em] text-[var(--primary)]">COMMUNITY</p>
     <h1 className="mt-1 text-3xl font-semibold">Кланы</h1>
     <p className="mt-1 text-sm text-[var(--muted-foreground)]">Все кланы PRISMA, их показатели, состав и управление.</p>
    </div>
    {!user.clan_id&&(
     <form action="/api/clans/create" method="post" className="flex gap-2">
      <input name="name" required minLength={2} maxLength={32} placeholder="Название нового клана" className="prisma-glass-control w-48 rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
      <button className="rounded-xl bg-[var(--primary)] px-4 py-2.5 text-sm font-semibold text-[var(--primary-foreground)]">Создать</button>
     </form>
    )}
   </div>

   {sp.error?<Card className="mt-4 border-red-500/30 p-4 text-sm text-red-400">{sp.error}</Card>:null}
   {sp.created?<Card className="mt-4 border-[var(--primary)]/30 bg-[rgba(113,225,172,.06)] p-4 text-sm">Клан успешно создан.</Card>:null}

   {user.clan_id?(
    <Card className="mt-5 border-[var(--primary)]/30 bg-[rgba(113,225,172,.06)] p-4">
     <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
       <p className="text-xs uppercase tracking-widest text-[var(--primary)]">Ваш клан</p>
       <p className="mt-1 font-semibold">{myClan?.name||sorted.find((c:any)=>c.id===user.clan_id)?.name||"Клан"}</p>
       <p className="mt-1 text-xs text-[var(--muted-foreground)]">Ваша роль: {roleLabel[myRole]||myRole||"Участник"}</p>
      </div>
      <div className="flex flex-wrap gap-2">
       <Link href={"/app/clans/"+user.clan_id} className="rounded-xl border px-3 py-2 text-xs font-semibold">Открыть профиль клана →</Link>
       {!isOwner?(
        <form action="/api/clans/action" method="post"><input type="hidden" name="action" value="leave"/><button className="rounded-xl border px-3 py-2 text-xs font-semibold prisma-glass-hover">Выйти из клана</button></form>
       ):null}
      </div>
     </div>
    </Card>
   ):null}

   {(incomingInvites.length||(canManage&&outgoingInvites.length))?(
    <Card className="mt-4 p-4">
     <div className="flex flex-wrap items-center justify-between gap-3">
      <div><p className="text-xs uppercase tracking-widest text-[var(--primary)]">Приглашения</p><p className="mt-1 text-sm text-[var(--muted-foreground)]">Входящие приглашения и отправленные заявки вашего клана.</p></div>
      <span className="rounded-full bg-[var(--muted)] px-2.5 py-1 text-xs font-semibold">{incomingInvites.length+(canManage?outgoingInvites.length:0)}</span>
     </div>
     {incomingInvites.length?(
      <div className="mt-3">
       <p className="mb-2 text-[10px] font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">Входящие</p>
       <div className="space-y-2">
        {incomingInvites.slice(0,5).map((invite:any)=>(
         <div key={invite.id} className="prisma-glass-surface prisma-glass-hover flex flex-wrap items-center justify-between gap-3 rounded-xl border p-3 text-sm">
          <div><span>{invite.name||invite.clans?.name||"Клан"} {invite.tag||invite.clans?.tag?"["+(invite.tag||invite.clans?.tag)+"]":""}</span>{invite.inviter_nickname?<p className="mt-1 text-[10px] text-[var(--muted-foreground)]">Пригласил: {invite.inviter_nickname}</p>:null}</div>
          <div className="flex gap-2">
           <form action="/api/clans/action" method="post"><input type="hidden" name="action" value="accept"/><input type="hidden" name="invite_id" value={invite.id}/><button className="rounded-lg bg-[var(--primary)] px-3 py-1.5 text-xs font-semibold text-[var(--primary-foreground)]">Принять</button></form>
           <form action="/api/clans/action" method="post"><input type="hidden" name="action" value="decline"/><input type="hidden" name="invite_id" value={invite.id}/><button className="rounded-lg border px-3 py-1.5 text-xs">Отклонить</button></form>
          </div>
         </div>
        ))}
       </div>
      </div>
     ):null}
     {canManage&&outgoingInvites.length?(
      <div className="mt-4 border-t pt-4">
       <div className="mb-2 flex items-center justify-between"><p className="text-[10px] font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">Отправленные</p><span className="text-xs text-[var(--muted-foreground)]">{outgoingInvites.length}</span></div>
       <div className="space-y-2">
        {outgoingInvites.slice(0,8).map((invite:any)=>(
         <div key={invite.id} className="prisma-glass-surface prisma-glass-hover flex flex-wrap items-center justify-between gap-3 rounded-xl border p-3 text-sm">
          <div><p className="font-medium">{invite.invitee_nickname||"Игрок"}</p><p className="mt-1 text-[10px] text-[var(--muted-foreground)]">Отправлено {new Date(invite.created_at).toLocaleDateString("ru-RU")} · до {new Date(invite.expires_at).toLocaleDateString("ru-RU")}</p></div>
          <form action="/api/clans/action" method="post"><input type="hidden" name="action" value="cancel_invite"/><input type="hidden" name="invite_id" value={invite.id}/><button className="rounded-lg border px-2.5 py-1.5 text-xs font-semibold">Отменить</button></form>
         </div>
        ))}
       </div>
      </div>
     ):null}
    </Card>
   ):null}

   {canRoleManage?(
    <div className="mt-5 grid gap-4 lg:grid-cols-3">
     <Card className="p-5">
      <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">УПРАВЛЕНИЕ</p>
      <h2 className="mt-2 font-semibold">Роли участников</h2>
      <p className="mt-1 text-xs text-[var(--muted-foreground)]">Новая роль не может быть равна или выше вашей. Владельца изменить здесь нельзя.</p>
      <form action="/api/clans/action" method="post" className="mt-4 space-y-2">
       <input name="target" required placeholder="Minecraft-ник участника" className="prisma-glass-control w-full rounded-md border px-3 py-2.5 text-sm"/>
       <div className="grid gap-2 sm:grid-cols-2">
        <select name="role" required className="prisma-glass-control rounded-md border px-3 py-2.5 text-sm">
         <option value="">Новая роль</option>
         {manageableRoles.map(role=><option key={role} value={role}>{roleLabel[role]}</option>)}
        </select>
        <button name="action" value="set_role" className="rounded-md bg-primary px-3 py-2.5 text-xs font-semibold text-primary-foreground">Изменить роль</button>
        {canManage?<button name="action" value="kick" className="rounded-md border px-3 py-2.5 text-xs font-semibold sm:col-span-2">Исключить</button>:null}
        {isOwner?<button name="action" value="transfer" className="rounded-md border px-3 py-2.5 text-xs font-semibold sm:col-span-2">Передать владельца</button>:null}
       </div>
      </form>
     </Card>

     {canManage ? <Card className="p-5">
      <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">ПРИГЛАШЕНИЕ</p>
      <h2 className="mt-2 font-semibold">Пригласить игрока</h2>
      <p className="mt-1 text-xs text-[var(--muted-foreground)]">Введите точный Minecraft-ник участника PRISMA.</p>
      <form action="/api/clans/action" method="post" className="mt-4 flex gap-2">
       <input type="hidden" name="action" value="invite"/>
       <input name="target" required maxLength={40} placeholder="Minecraft-ник" className="prisma-glass-control min-w-0 flex-1 rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <button className="rounded-md bg-primary px-4 py-2.5 text-xs font-semibold text-primary-foreground">Пригласить</button>
      </form>
     </Card> : <Card className="p-5">
      <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">ПОЛНОМОЧИЯ</p>
      <h2 className="mt-2 font-semibold">Операционное управление</h2>
      <p className="mt-1 text-xs leading-5 text-muted-foreground">Приглашения, объявления и управление войнами доступны владельцу и офицеру.</p>
     </Card>}

     <Card className="p-5">
      <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">CLAN WAR</p>
      <h2 className="mt-2 font-semibold">Войны кланов</h2>
      <p className="mt-1 text-xs text-[var(--muted-foreground)]">Вызов → принятие → начало → результат. Все изменения проходят через единый серверный lifecycle.</p>

      {pendingWars.length ? (
       <div className="mt-4 space-y-2">
        {pendingWars.map((w:any)=>(
         <div key={w.id} className="prisma-glass-surface rounded-lg border p-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
           <div>
            <p className="text-sm font-medium">{w.incoming?"Входящий вызов":"Ваш вызов"} · [{w.opponent_tag||"—"}] {w.opponent||"Клан"}</p>
            <p className="mt-1 text-xs text-muted-foreground">{w.incoming?"Ожидает вашего ответа.":"Ожидает ответа соперника."}</p>
           </div>
           <div className="flex gap-2">
            {w.can_respond ? <form action="/api/clans/action" method="post">
             <input type="hidden" name="action" value="war_accept"/>
             <input type="hidden" name="target" value={w.id}/>
             <button className="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground">Принять</button>
            </form> : null}
            {w.can_respond ? <form action="/api/clans/action" method="post">
             <input type="hidden" name="action" value="war_decline"/>
             <input type="hidden" name="target" value={w.id}/>
             <button className="rounded-md border px-3 py-1.5 text-xs font-medium">Отклонить</button>
            </form> : null}
            {!w.incoming && canManage ? <form action="/api/clans/action" method="post">
             <input type="hidden" name="action" value="war_cancel"/>
             <input type="hidden" name="target" value={w.id}/>
             <button className="rounded-md border px-3 py-1.5 text-xs font-medium">Отменить</button>
            </form> : null}
           </div>
          </div>
         </div>
        ))}
       </div>
      ) : null}

      {activeWars.length ? (
       <div className="mt-4 space-y-2">
        {activeWars.slice(0,5).map((w:any)=>(
         <div key={w.id} className="prisma-glass-surface rounded-lg border p-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
           <div>
            <p className="text-sm font-medium">[{w.opponent_tag||"—"}] {w.opponent||"Клан"}</p>
            <p className="mt-1 text-xs text-muted-foreground">
             {w.status==="scheduled"?"Запланирована":"Идёт"} · {w.score_for ?? 0}:{w.score_against ?? 0}
             {w.scheduled_at ? " · " + new Date(w.scheduled_at).toLocaleString("ru-RU") : ""}
            </p>
           </div>
           <div className="flex flex-wrap gap-2">
            {w.can_start ? <form action="/api/clans/action" method="post">
             <input type="hidden" name="action" value="war_start"/>
             <input type="hidden" name="target" value={w.id}/>
             <button className="rounded-md bg-foreground px-3 py-1.5 text-xs font-medium text-background">Начать</button>
            </form> : null}
            {w.can_finish ? <form action="/api/clans/action" method="post" className="flex flex-wrap gap-2">
             <input type="hidden" name="action" value="war_finish"/>
             <input type="hidden" name="target" value={w.id}/>
             <input name="score_a" required type="number" min={0} placeholder="Счёт A" className="prisma-glass-control w-20 rounded-md border px-2 py-1.5 text-xs text-foreground"/>
             <input name="score_b" required type="number" min={0} placeholder="Счёт B" className="prisma-glass-control w-20 rounded-md border px-2 py-1.5 text-xs text-foreground"/>
             <button className="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground">Завершить</button>
            </form> : null}
            {canManage && !w.can_finish ? <form action="/api/clans/action" method="post">
             <input type="hidden" name="action" value="war_cancel"/>
             <input type="hidden" name="target" value={w.id}/>
             <button className="rounded-md border px-3 py-1.5 text-xs font-medium">Отменить</button>
            </form> : null}
           </div>
          </div>
         </div>
        ))}
       </div>
      ) : null}

      {!warItems.length ? <div className="mt-4 rounded-md border border-dashed p-4 text-sm text-muted-foreground">У вашего клана пока нет активных вызовов.</div> : null}

      {canManage ? (
       <form action="/api/clans/action" method="post" className="mt-4 flex flex-wrap gap-2 border-t pt-4">
        <input type="hidden" name="action" value="war"/>
        <select name="target" required className="prisma-glass-control min-w-0 flex-1 rounded-md border px-3 py-2.5 text-sm text-foreground">
         <option value="">Выберите клан для вызова</option>
         {selectableClans.map((c:any)=><option key={c.id} value={c.tag||c.name}>[{c.tag||"—"}] {c.name}</option>)}
        </select>
        <button className="rounded-md bg-foreground px-4 py-2.5 text-xs font-medium text-background">Объявить войну</button>
       </form>
      ) : null}
     </Card>
    </div>
   ):null}

   {isOwner?(
    <Card className="mt-4 p-5">
     <div><p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">ПРОФИЛЬ КЛАНА</p><h2 className="mt-2 font-semibold">Настройка клана</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Название, тег, описание и режим вступления видны участникам PRISMA.</p></div>
     <form action="/api/clans/action" method="post" className="mt-4 grid gap-3 sm:grid-cols-2">
      <input type="hidden" name="action" value="clan_update"/>
      <input name="name" required minLength={2} maxLength={32} defaultValue={myClan?.name||""} placeholder="Название" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
      <input name="tag" required minLength={2} maxLength={6} pattern="[A-Za-z0-9]{2,6}" defaultValue={myClan?.tag||""} placeholder="Тег, например PRSM" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
      <textarea name="description" maxLength={500} defaultValue={myClan?.description||""} placeholder="Описание клана" className="prisma-glass-control min-h-24 rounded-xl border px-3 py-2.5 text-sm text-foreground sm:col-span-2"/>
      <select name="type" defaultValue={String(myClan?.type||"open")} className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"><option value="open">Открытый — можно вступить сразу</option><option value="closed">Закрытый — только по приглашению</option></select>
      <button className="rounded-xl bg-[var(--primary)] px-4 py-2.5 text-xs font-semibold text-[var(--primary-foreground)]">Сохранить профиль</button>
     </form>
    </Card>
   ):null}

   {canManage?(
    <Card className="mt-4 p-5">
     <div className="flex items-center justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">ОБЪЯВЛЕНИЯ</p><h2 className="mt-2 font-semibold">Новости клана</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Сообщения, которые увидят участники в профиле клана.</p></div><span className="text-xs text-[var(--muted-foreground)]">{myAnnouncements.length}</span></div>
     <form action="/api/clans/action" method="post" className="mt-4 grid gap-2">
      <input type="hidden" name="action" value="announcement_create"/>
      <input name="title" required minLength={3} maxLength={120} placeholder="Заголовок объявления" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
      <textarea name="body" required minLength={3} maxLength={3000} placeholder="Текст объявления" className="min-h-24 rounded-xl border px-3 py-2.5 text-sm"/>
      <button className="rounded-xl bg-[var(--primary)] px-4 py-2.5 text-xs font-semibold text-[var(--primary-foreground)]">Опубликовать</button>
     </form>
     {myAnnouncements.length?<div className="mt-4 space-y-2">{myAnnouncements.slice(0,5).map((a:any)=><div key={a.id} className="prisma-glass-surface prisma-glass-hover flex items-start justify-between gap-3 rounded-xl border p-3"><div className="min-w-0"><p className="text-xs font-semibold">{a.title}</p><p className="mt-1 line-clamp-2 text-[11px] leading-5 text-[var(--muted-foreground)]">{a.body}</p></div><form action="/api/clans/action" method="post"><input type="hidden" name="action" value="announcement_delete"/><input type="hidden" name="announcement_id" value={a.id}/><button className="rounded-lg border px-2.5 py-1.5 text-[10px] font-semibold">Удалить</button></form></div>)}</div>:null}
    </Card>
   ):null}

   {isOwner?(
    <div className="mt-4 grid gap-4 lg:grid-cols-2">
     <Card className="p-5">
      <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">ТЕРРИТОРИЯ</p>
      <h2 className="mt-2 font-semibold">Территории клана</h2>
      {myVillages.length?<div className="mt-4 space-y-2">{myVillages.slice(0,6).map((v:any)=><div key={v.id} className="prisma-glass-surface prisma-glass-hover flex items-center justify-between gap-3 rounded-xl border p-3"><div className="min-w-0"><p className="truncate text-xs font-semibold">{v.name}</p><p className="mt-1 text-[10px] text-[var(--muted-foreground)]">{v.world} · X {Math.round(v.center_x)} · Z {Math.round(v.center_z)} · R{v.radius}</p></div><form action="/api/clans/action" method="post"><input type="hidden" name="action" value="village_delete"/><input type="hidden" name="village_id" value={v.id}/><button className="rounded-lg border px-2.5 py-1.5 text-[10px] font-semibold">Удалить</button></form></div>)}</div>:<p className="mt-3 text-xs text-[var(--muted-foreground)]">Территорий пока нет.</p>}
      <form action="/api/clans/action" method="post" className="mt-5 grid gap-2 sm:grid-cols-2">
       <input type="hidden" name="action" value="village_create"/>
       <input name="name" required minLength={2} maxLength={80} placeholder="Название" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <input name="world" required maxLength={80} placeholder="Мир" defaultValue="world" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <input name="x" required type="number" step="any" placeholder="X" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <input name="y" required type="number" step="any" defaultValue="64" placeholder="Y" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <input name="z" required type="number" step="any" placeholder="Z" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <input name="radius" required type="number" min="8" max="512" defaultValue="48" placeholder="Радиус" className="prisma-glass-control rounded-xl border px-3 py-2.5 text-sm text-foreground"/>
       <button className="rounded-xl bg-[var(--primary)] px-4 py-2.5 text-xs font-semibold text-[var(--primary-foreground)] sm:col-span-2">Создать территорию</button>
      </form>
     </Card>

     <Card className="p-5">
      <p className="text-xs font-semibold uppercase tracking-widest text-red-400">ОПАСНАЯ ЗОНА</p>
      <h2 className="mt-2 font-semibold">Распустить клан</h2>
      <p className="mt-1 text-xs leading-5 text-[var(--muted-foreground)]">Это удалит активный статус клана, снимет участников и деактивирует территории.</p>
      <form action="/api/clans/action" method="post" className="mt-4 space-y-3">
       <input type="hidden" name="action" value="disband"/>
       <label className="flex items-start gap-2 text-xs"><input type="checkbox" name="confirm" value="yes" required className="mt-0.5"/><span>Я понимаю, что распуск клана необратим.</span></label>
       <button className="rounded-xl border border-red-500/40 px-4 py-2.5 text-xs font-semibold text-red-400">Распустить клан</button>
      </form>
     </Card>
    </div>
   ):null}

   <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
    {sorted.map((clan:any)=>{
     const list=Array.isArray(clan.members)?clan.members:[];
     const mine=clan.id===user.clan_id;
     const open=String(clan.type||"").toLowerCase()==="open";
     return(
      <Card key={clan.id} className={"flex h-full flex-col overflow-hidden "+(mine?"border-[var(--primary)]/45":"")}>
       <div className="border-b p-5">
        <div className="flex items-start justify-between gap-3">
         <div>
          <p className="text-lg font-semibold">{clan.name} <span className="text-[var(--muted-foreground)]">[{clan.tag||"—"}]</span></p>
          <p className="mt-1 text-xs text-[var(--muted-foreground)]">Владелец: {clan.owner_nickname||"Не указан"}</p>
         </div>
         <span className="prisma-glass-badge rounded-full border px-2.5 py-1 text-[10px] font-semibold">{open?"Открытый":"Закрытый"}</span>
        </div>
        <p className="mt-3 line-clamp-2 text-sm leading-6 text-[var(--muted-foreground)]">{clan.description||"Без описания."}</p>
       </div>
       <div className="grid grid-cols-3 gap-2 p-4">
        {[[ "RR",clan.rating||0 ],["Lvl",clan.level||1],["W/L",(clan.wins||0)+"/"+(clan.losses||0)]].map(([k,v])=><div key={String(k)} className="prisma-glass-surface rounded-xl border p-3 text-center"><p className="text-[10px] text-[var(--muted-foreground)]">{String(k)}</p><p className="mt-1 text-sm font-semibold">{String(v)}</p></div>)}
       </div>
       <div className="flex-1 border-t p-4">
        <div className="flex items-center justify-between"><p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">Участники</p><span className="text-xs text-[var(--muted-foreground)]">{Number(clan.member_count||0)}</span></div>
        <div className="mt-3 flex flex-wrap gap-1.5">
         {list.map((member:any)=><Link key={member.user_id} href={member.minecraft_nickname?"/players/"+encodeURIComponent(member.minecraft_nickname):"#"} className="rounded-lg border px-2 py-1 text-xs hover:border-[var(--primary)]/40">{member.minecraft_nickname||"Игрок"}<span className="ml-1 text-[10px] text-[var(--muted-foreground)]">{roleLabel[member.role]||""}</span></Link>)}
         {Number(clan.member_count||0)>list.length?<span className="prisma-glass-badge rounded-lg border px-2 py-1 text-xs">+{Number(clan.member_count)-list.length}</span>:null}
        </div>
       </div>
       <div className="flex items-center gap-2 border-t p-4">
        {mine?<Link href={"/app/clans/"+clan.id} className="flex-1 rounded-xl border px-3 py-2.5 text-center text-xs font-semibold">Ваш клан</Link>:open&&!user.clan_id?<form action="/api/clans/action" method="post" className="flex-1"><input type="hidden" name="action" value="join"/><input type="hidden" name="target" value={clan.id}/><button className="w-full rounded-xl bg-[var(--primary)] px-3 py-2.5 text-xs font-semibold text-[var(--primary-foreground)]">Вступить</button></form>:<span className="flex-1 rounded-xl border px-3 py-2.5 text-center text-xs text-[var(--muted-foreground)]">{user.clan_id?"Вы уже в клане":"Вступление по приглашению"}</span>}
        <Link href={"/app/clans/"+clan.id} className="rounded-xl border px-3 py-2.5 text-xs font-semibold">Подробнее</Link>
       </div>
      </Card>
     );
    })}
    {!sorted.length?<Card className="p-10 text-center md:col-span-2 xl:col-span-3"><p className="font-semibold">Кланов пока нет</p><p className="mt-1 text-sm text-[var(--muted-foreground)]">Создайте первый клан PRISMA.</p></Card>:null}
   </div>
  </div>
 );
}