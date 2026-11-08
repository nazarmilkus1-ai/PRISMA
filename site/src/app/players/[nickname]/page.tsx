import Link from "next/link";
import {notFound} from "next/navigation";
import { getPublicModuleAvailability } from "@/lib/modules";
import {requireMember} from "@/lib/member";
import {getPlayerProfile,getSocialData} from "@/lib/data";
import {Card} from "@/components/Card";
import {ProgressBar,SectionTitle,StatCard} from "@/components/SitePrimitives";

function fmtMinutes(v:number){
 const d=Math.floor(v/1440),h=Math.floor(v%1440/60),m=v%60;
 return d?d+" дн "+h+" ч":h?h+" ч "+m+" мин":m+" мин";
}

export default async function PlayerPage({
 params,
 searchParams,
}:{
 params:Promise<{nickname:string}>;
 searchParams:Promise<{social_error?:string;social_done?:string}>;
}){
  const enabledModules = await getPublicModuleAvailability();
  if (!enabledModules.players) notFound();
 const viewer=await requireMember();
 const{nickname}=await params;
 const sp=await searchParams;
 const [data,viewerSocial]=await Promise.all([
  getPlayerProfile(decodeURIComponent(nickname)),
  enabledModules.social ? getSocialData() : Promise.resolve(null),
 ]);
 if(!data)return notFound();

 const history=data.rating_history??[];
 const publicSocial=data.social||{visibility:"PRIVATE"};
 const s=data.stats||{};
 const kills=s.kills??0;
 const deaths=s.deaths??0;
 const kd=deaths?(kills/deaths).toFixed(2):kills.toFixed(2);
 const achievements=data.achievements??[];
 const online=data.user.last_seen_at?Date.now()-new Date(data.user.last_seen_at).getTime()<120000:false;
 const serverRole=data.server_role||"Участник";
 const links:any=data.user.profile_links||{};

 return <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6">
  {enabledModules.social ? <>
   {sp.social_error?<div className="rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">{decodeURIComponent(sp.social_error)}</div>:null}
   {sp.social_done?<div className="rounded-xl border border-primary/30 bg-primary/5 px-4 py-3 text-sm">Социальный запрос отправлен или действие выполнено.</div>:null}
  </> : null}
  <div className="flex flex-wrap items-end justify-between gap-4">
   <div>
    <SectionTitle eyebrow="PLAYER PASSPORT" title={data.user.minecraft_nickname} description={data.clan?"["+data.clan.tag+"] "+data.clan.name+" · "+(data.membership?.role||"member"):"Без клана"}/>
    <div className="mt-3 flex flex-wrap gap-2">
     <span className="rounded-full border px-3 py-1.5 text-xs font-semibold">{online?"🟢 Online":"⚪ Offline"}</span>
     <span className="rounded-full border px-3 py-1.5 text-xs font-semibold">Роль: {serverRole}</span>
     <span className="rounded-full border px-3 py-1.5 text-xs font-semibold">Репутация: {data.user.activity_score??0}</span>
    </div>
   </div>
   <div className="flex gap-2">
    {enabledModules.battles ? <Link href="/app/battles" className="rounded-xl bg-[var(--primary)] px-4 py-2.5 text-sm font-semibold text-[var(--primary-foreground)]">Player Battle</Link> : null}
    <Link href="/app/players" className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm">← Игроки</Link>
   </div>
  </div>

  {enabledModules.social && viewerSocial && viewer.minecraft_nickname &&
   viewer.minecraft_nickname.toLowerCase() !== data.user.minecraft_nickname.toLowerCase() &&
   !viewer.is_banned ? (
    <Card className="mt-6 p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="font-semibold">Связаться через PRISMA</h2>
          <p className="mt-1 text-sm text-[var(--muted-foreground)]">
            Социальные запросы отправляются напрямую этому участнику.
          </p>
        </div>
        <span className="rounded-full border px-3 py-1.5 text-xs font-semibold">PRISMA Social</span>
      </div>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <form action="/api/profile/social" method="post">
          <input type="hidden" name="action" value="MARRIAGE_REQUEST" />
          <input type="hidden" name="target" value={data.user.minecraft_nickname} />
          <input type="hidden" name="return_to" value={"/players/"+encodeURIComponent(data.user.minecraft_nickname)} />
          <button
            type="submit"
            disabled={!!viewerSocial.marriage}
            className="prisma-glass-control prisma-glass-hover w-full rounded-xl border px-4 py-3 text-left text-sm font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span className="block">💍 Предложение о браке</span>
            <span className="mt-1 block text-xs font-normal text-[var(--muted-foreground)]">
              {viewerSocial.marriage ? "У вас уже есть активный брак." : "Создать предложение этому игроку."}
            </span>
          </button>
        </form>
        <form action="/api/profile/social" method="post">
          <input type="hidden" name="action" value="RELATIONSHIP_REQUEST" />
          <input type="hidden" name="target" value={data.user.minecraft_nickname} />
          <input type="hidden" name="return_to" value={"/players/"+encodeURIComponent(data.user.minecraft_nickname)} />
          <button
            type="submit"
            disabled={!!viewerSocial.relationship}
            className="prisma-glass-control prisma-glass-hover w-full rounded-xl border px-4 py-3 text-left text-sm font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span className="block">❤️ Запрос на отношения</span>
            <span className="mt-1 block text-xs font-normal text-[var(--muted-foreground)]">
              {viewerSocial.relationship ? "У вас уже есть активные отношения." : "Отправить запрос этому игроку."}
            </span>
          </button>
        </form>
      </div>
    </Card>
  ) : null}

  <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
   <StatCard label="Рейтинг" value={data.user.rating??0} caption="PRISMA rating"/>
   <StatCard label="Репутация" value={data.user.activity_score??0} caption="activity / reputation"/>
   <StatCard label="Уровень" value={data.user.level??1} caption={(data.user.xp??0)+" XP"}/>
   <StatCard label="Достижения" value={achievements.length} caption="разблокировано"/>
  </div>

  <div className="mt-6 grid gap-6 lg:grid-cols-[1.5fr_1fr]">
   <Card className="p-6">
    <h2 className="font-semibold">Статистика Minecraft</h2>
    <div className="mt-5 grid gap-4 sm:grid-cols-2">
     {[
      ["Убийства",kills],
      ["Смерти",deaths],
      ["K/D",kd],
      ["Время в игре",fmtMinutes(s.playtime_minutes??0)],
      ["Поставлено блоков",s.blocks_placed??0],
      ["Сломано блоков",s.blocks_broken??0],
      ["Убито мобов",s.mobs_killed??0],
      ["Дистанция",(s.distance_walked??0)+" м"]
     ].map(([k,v])=><div key={String(k)} className="rounded-2xl border bg-[var(--muted)] p-4"><p className="text-xs text-[var(--muted-foreground)]">{k}</p><p className="mt-1 text-xl font-semibold">{v}</p></div>)}
    </div>
    <div className="mt-6 space-y-4">
     <ProgressBar label="Баланс убийств / смертей" value={kills} max={Math.max(1,kills+deaths)} caption={Math.round(kills/Math.max(1,kills+deaths)*100)+"%"}/>
     <ProgressBar label="Строительная активность" value={(s.blocks_placed??0)+(s.blocks_broken??0)} max={Math.max(1,(s.blocks_placed??0)+(s.blocks_broken??0))}/>
    </div>
   </Card>

   <Card className="p-6">
    <h2 className="font-semibold">Достижения</h2>
    <div className="mt-4 space-y-3">
     {achievements.slice(0,8).map((a:any)=><div key={a.achievement_id} className="rounded-xl border p-3"><p className="text-sm font-semibold">{a.achievements?.icon||"◆"} {a.achievements?.title||"Достижение"}</p><p className="mt-1 text-xs text-[var(--muted-foreground)]">{a.achievements?.description||"Разблокировано"}</p></div>)}
    </div>
   </Card>
  </div>

  {Object.values(links).some(Boolean)?<Card className="mt-6 p-6">
   <h2 className="font-semibold">Ссылки</h2>
   <div className="mt-4 flex flex-wrap gap-2">
    {([["website","Сайт"],["discord","Discord"],["youtube","YouTube"],["telegram","Telegram"]] as const).map(([key,label])=>links[key]?<a key={key} href={links[key]} target="_blank" rel="noreferrer noopener" className="prisma-glass-control prisma-glass-hover rounded-xl border px-3 py-2 text-xs font-semibold">{label}</a>:null)}
   </div>
  </Card>:null}

  {enabledModules.social ? (
  <Card className="mt-6 p-6">
   <div className="flex items-center justify-between gap-3">
    <div>
     <h2 className="font-semibold">Социальный статус</h2>
     <p className="mt-1 text-xs text-[var(--muted-foreground)]">Показывается только по настройке владельца профиля.</p>
    </div>
    <span className="rounded-full border px-3 py-1.5 text-xs font-semibold">
     {publicSocial.visibility==="PUBLIC"?"Открыт":"Скрыт"}
    </span>
   </div>
   {publicSocial.visibility==="PUBLIC" ? (
    <div className="mt-4 grid gap-3 sm:grid-cols-2">
     <div className="rounded-xl border p-4">
      <p className="text-xs text-[var(--muted-foreground)]">Брак</p>
      {publicSocial.marriage?.partner_nickname ? (
       <Link href={"/players/"+encodeURIComponent(publicSocial.marriage.partner_nickname)} className="mt-2 block text-sm font-semibold hover:underline">
        {publicSocial.marriage.partner_nickname}
       </Link>
      ) : <p className="mt-2 text-sm text-[var(--muted-foreground)]">Нет активного статуса</p>}
     </div>
     <div className="rounded-xl border p-4">
      <p className="text-xs text-[var(--muted-foreground)]">Отношения</p>
      {publicSocial.relationship?.partner_nickname ? (
       <Link href={"/players/"+encodeURIComponent(publicSocial.relationship.partner_nickname)} className="mt-2 block text-sm font-semibold hover:underline">
        {publicSocial.relationship.partner_nickname}
       </Link>
      ) : <p className="mt-2 text-sm text-[var(--muted-foreground)]">Нет активного статуса</p>}
     </div>
    </div>
   ) : (
    <p className="mt-4 text-sm text-[var(--muted-foreground)]">Владелец профиля не показывает социальный статус.</p>
   )}
  </Card>
  ) : null}

  <Card className="mt-6 p-6">
   <div className="flex items-center justify-between"><h2 className="font-semibold">История рейтинга</h2><span className="text-xs text-[var(--muted-foreground)]">{history.length} изменений</span></div>
   <div className="mt-4 flex h-28 items-end gap-1">
    {[...history].reverse().map((h:any,i:number)=>{
     const max=Math.max(1,...history.map((x:any)=>x.rating));
     return <div key={i} title={new Date(h.created_at).toLocaleString("ru-RU")+" · "+h.reason} className="flex-1 rounded-t bg-[var(--primary)]" style={{height:Math.max(8,h.rating/max*100)+"%"}}/>
    })}
   </div>
   <div className="mt-4 grid gap-2 sm:grid-cols-2">
    {history.slice(0,8).map((h:any)=><div key={h.created_at+h.reason} className="prisma-glass-surface flex justify-between rounded-xl border px-3 py-2 text-xs"><span>{h.reason}</span><b>{h.delta>0?"+":""}{h.delta} · {h.rating}</b></div>)}
   </div>
  </Card>

  <Card className="mt-6 p-6">
   <div className="flex items-center justify-between"><h2 className="font-semibold">История активности</h2><span className="text-xs text-[var(--muted-foreground)]">{data.activity.length} записей</span></div>
   <div className="mt-4 divide-y">
    {data.activity.slice(0,12).map((e:any)=><div key={e.id} className="flex items-center justify-between gap-4 py-3"><div><p className="text-sm font-medium">{e.source}</p><p className="text-xs text-[var(--muted-foreground)]">{e.metadata?.title||e.metadata?.description||"Активность PRISMA"}</p></div><span className="text-xs font-semibold">{e.points>0?"+":""}{e.points}</span></div>)}
   </div>
  </Card>
 </div>;
}