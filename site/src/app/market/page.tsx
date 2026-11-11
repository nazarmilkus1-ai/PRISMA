import { requireModuleMember } from "@/lib/access";
import { redirect } from "next/navigation";
import {getMarket,getMarketInquiries, getMarketOffers} from "@/lib/data";
import {Card} from "@/components/Card";
import {SectionTitle,EmptyState} from "@/components/SitePrimitives";

export const metadata={title:"Рынок"};

export default async function MarketPage({searchParams}:{searchParams:Promise<{q?:string;kind?:string;created?:string;closed?:string;updated?:string;inquiry_sent?:string;inquiry_updated?:string;inquiry_closed?:string;offer_sent?:string;offer_updated?:string;error?:string}>}){
 const user=await requireModuleMember("market");
 if(!user.is_whitelisted) redirect("/?memberOnly=1");
 const sp=await searchParams;
 const q=sp.q||"",kind=sp.kind||"";
 const [listings,inquiries,offers]=await Promise.all([
   getMarket(kind||undefined,q),
   getMarketInquiries(),
   getMarketOffers(),
 ]);
 const hiddenReturn=<><input type="hidden" name="return_q" value={q}/><input type="hidden" name="return_kind" value={kind}/></>;

 return <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6">
  <SectionTitle eyebrow="MARKET" title="Рынок PRISMA" description="Объявления участников: продам, куплю, обменяю, помогу построить. Без внутренней валюты — цена и условия указываются свободно."/>
  <Card className="mt-6 p-5">
   {sp.created?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Объявление опубликовано.</p>:null}
   {sp.updated?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Объявление обновлено.</p>:null}
   {sp.closed?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Объявление снято с публикации.</p>:null}
   {sp.error?<p className="mb-4 rounded-xl border border-red-500/30 px-4 py-3 text-sm text-red-400">Не удалось выполнить действие: {sp.error}</p>:null}
   {sp.inquiry_sent?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Запрос отправлен владельцу объявления.</p>:null}
   {sp.inquiry_updated?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Ответ отправлен.</p>:null}
   {sp.offer_sent?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Предложение отправлено. Продавец ответит в течение 72 часов.</p>:null}
   {sp.offer_updated?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Готово.</p>:null}
   {sp.inquiry_closed?<p className="mb-4 prisma-glass-surface rounded-xl border border-primary/30 px-4 py-3 text-sm">Запрос закрыт.</p>:null}

   <form action={user ? "/app/market" : "/market"} className="grid gap-3 md:grid-cols-[1fr_180px_auto]">
    <input name="q" defaultValue={q} placeholder="Поиск объявлений" className="prisma-glass-control rounded-xl border px-4 py-3 text-sm"/>
    <select name="kind" defaultValue={kind} className="prisma-glass-control rounded-xl border px-3 py-3 text-sm">
     <option value="">Все</option><option value="SELL">Продам</option><option value="BUY">Куплю</option><option value="TRADE">Обмен</option><option value="SERVICE">Услуга</option><option value="OTHER">Другое</option>
    </select>
    <button className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-3 text-sm font-semibold text-foreground">Поиск</button>
   </form>

   {(
   <form action="/api/market" method="post" className="mt-5 grid gap-3 border-t pt-5 md:grid-cols-2">
    <select name="kind" required className="prisma-glass-control rounded-xl border px-3 py-3 text-sm"><option value="SELL">Продам</option><option value="BUY">Куплю</option><option value="TRADE">Обменяю</option><option value="SERVICE">Помогу / услуга</option><option value="OTHER">Другое</option></select>
    <input name="title" required minLength={3} maxLength={100} placeholder="Заголовок" className="prisma-glass-control rounded-xl border px-3 py-3 text-sm"/>
    <textarea name="description" maxLength={1000} placeholder="Что предлагаете / ищете" className="rounded-xl border px-3 py-3 text-sm md:col-span-2"/>
    <input name="price_text" maxLength={200} placeholder="Цена / вознаграждение / условия" className="prisma-glass-control rounded-xl border px-3 py-3 text-sm"/>
    <input name="terms" maxLength={500} placeholder="Дополнительные условия" className="prisma-glass-control rounded-xl border px-3 py-3 text-sm"/>
    <select name="expiry_days" defaultValue="14" className="prisma-glass-control rounded-xl border px-3 py-3 text-sm">
      <option value="0">Без срока</option><option value="1">На 1 день</option><option value="3">На 3 дня</option>
      <option value="7">На 7 дней</option><option value="14">На 14 дней</option><option value="30">На 30 дней</option>
    </select>
    {hiddenReturn}
    <button className="prisma-glass-primary prisma-glass-shimmer rounded-xl border px-4 py-3 text-sm font-semibold text-primary md:col-span-2">Опубликовать объявление</button>
   </form>
   )}
  </Card>

  {offers.length>0?<Card className="mt-6 p-5">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Торг</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Предложения цены: принять, отклонить или предложить свою. На ответ даётся 72 часа, до 6 раундов.</p></div><span className="prisma-glass-badge rounded-full border px-3 py-1 text-xs font-semibold">{offers.length}</span></div>
    <div className="mt-4 grid gap-3 md:grid-cols-2">
      {offers.map((o:any)=><div key={o.id} className="prisma-glass-surface rounded-2xl border p-4">
        <p className="text-sm font-semibold">{o.listing_title}</p>
        <p className="mt-1 text-xs text-[var(--muted-foreground)]">{o.mine?"Вы предложили":`${o.partner_nickname||"Участник"} предлагает`}: <b className="text-[var(--foreground)]">{o.price_text}</b> · {o.expired?"истекло":({PENDING:"ждёт ответа",ACCEPTED:"принято",REJECTED:"отклонено",COUNTERED:"есть встречное",WITHDRAWN:"отозвано"} as Record<string,string>)[o.status]||o.status} · раунд {o.round}/6</p>
        {o.note?<p className="mt-1 text-xs text-[var(--muted-foreground)]">{o.note}</p>:null}
        {o.actionable?<form action="/api/market" method="post" className="mt-3 space-y-2">
          <input type="hidden" name="action" value="offer_respond"/><input type="hidden" name="offer_id" value={o.id}/>{hiddenReturn}
          <div className="flex flex-wrap gap-2">
            <button name="answer" value="accept" className="rounded-lg bg-[var(--primary)] px-3 py-2 text-xs font-semibold text-[var(--primary-foreground)]">Принять</button>
            <button name="answer" value="reject" className="prisma-glass-control rounded-lg border px-3 py-2 text-xs font-semibold">Отклонить</button>
          </div>
          <div className="flex flex-wrap gap-2">
            <input name="price" maxLength={60} placeholder="Встречная цена" className="prisma-glass-control min-w-0 flex-1 rounded-lg border px-3 py-2 text-xs"/>
            <button name="answer" value="counter" formNoValidate className="prisma-glass-control rounded-lg border px-3 py-2 text-xs font-semibold">Предложить свою</button>
          </div>
        </form>:null}
        {o.mine&&o.status==="PENDING"&&!o.expired?<form action="/api/market" method="post" className="mt-3"><input type="hidden" name="action" value="offer_withdraw"/><input type="hidden" name="offer_id" value={o.id}/>{hiddenReturn}<button className="prisma-glass-control rounded-lg border px-3 py-1.5 text-xs font-semibold">Отозвать</button></form>:null}
      </div>)}
    </div>
  </Card>:null}

  {inquiries.length>0?<Card className="mt-6 p-5">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Запросы по объявлениям</h2><p className="mt-1 text-xs text-[var(--muted-foreground)]">Входящие запросы от покупателей и ваши обращения к участникам.</p></div><span className="prisma-glass-badge rounded-full border px-3 py-1 text-xs font-semibold">{inquiries.length}</span></div>
    <div className="mt-4 space-y-3">
      {inquiries.map((i:any)=><div key={i.id} className="prisma-glass-surface rounded-2xl border p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div><p className="text-sm font-semibold">{i.listing_title}</p><p className="mt-1 text-xs text-[var(--muted-foreground)]">{i.incoming?"От "+i.partner_nickname:"К "+i.partner_nickname} · {i.status==="OPEN"?"Ожидает ответа":i.status==="ANSWERED"?"Есть ответ":"Закрыт"}</p></div>
          {i.status!=="CLOSED"?<form action="/api/market" method="post"><input type="hidden" name="action" value="inquiry_close"/><input type="hidden" name="inquiry_id" value={i.id}/><input type="hidden" name="return_q" value={q}/><input type="hidden" name="return_kind" value={kind}/><button className="prisma-glass-control prisma-glass-hover rounded-lg border px-3 py-1.5 text-xs font-semibold">Закрыть</button></form>:null}
        </div>
        <p className="mt-3 whitespace-pre-wrap prisma-glass-surface rounded-xl border px-3 py-2.5 text-sm leading-6">{i.message}</p>
        {i.response?<div className="prisma-glass-surface mt-2 whitespace-pre-wrap rounded-xl border px-3 py-2.5 text-sm leading-6"><p className="mb-1 text-[10px] font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">Ответ</p>{i.response}</div>:null}
        {i.incoming&&i.status!=="CLOSED"?<form action="/api/market" method="post" className="mt-3 space-y-2"><input type="hidden" name="action" value="inquiry_response"/><input type="hidden" name="inquiry_id" value={i.id}/><input type="hidden" name="return_q" value={q}/><input type="hidden" name="return_kind" value={kind}/><textarea name="response" required minLength={3} maxLength={1500} placeholder="Ответ участнику" className="prisma-glass-control min-h-20 w-full rounded-xl border px-3 py-2.5 text-sm"/><button className="rounded-xl bg-[var(--primary)] px-4 py-2.5 text-xs font-semibold text-[var(--primary-foreground)]">Ответить</button></form>:null}
      </div>)}
    </div>
  </Card>:null}

  <div className="mt-6 grid gap-4 lg:grid-cols-2">
   {listings.map((x:any)=><Card key={x.id} className="p-5">
    <div className="flex items-start justify-between gap-3"><div><span className="prisma-glass-badge rounded-full border px-2 py-1 text-[11px] font-semibold">{x.kind}</span><h2 className="mt-3 text-lg font-semibold">{x.title}</h2></div><span className="text-xs text-[var(--muted-foreground)]">{x.users?.minecraft_nickname||"Участник"}</span></div>
    <p className="mt-3 text-sm leading-6 text-[var(--muted-foreground)]">{x.description}</p>
    {x.price_text&&<p className="mt-4 prisma-glass-surface rounded-xl border px-4 py-3 text-sm font-semibold">{x.price_text}</p>}
    {x.terms&&<p className="mt-2 text-xs text-[var(--muted-foreground)]">{x.terms}</p>}
    {x.expires_at&&<p className="mt-2 text-xs text-[var(--muted-foreground)]">Действует до {new Date(x.expires_at).toLocaleString("ru-RU")}</p>}

    {user && x.seller_id!==user.id?(
      <details className="prisma-glass-surface mt-4 rounded-xl border">
       <summary className="prisma-glass-hover cursor-pointer list-none px-3 py-2 text-xs font-semibold">Написать владельцу</summary>
       <form action="/api/market" method="post" className="space-y-2 border-t p-3">
        <input type="hidden" name="action" value="inquiry_create"/><input type="hidden" name="listing_id" value={x.id}/><input type="hidden" name="return_q" value={q}/><input type="hidden" name="return_kind" value={kind}/>
        <textarea name="message" required minLength={3} maxLength={1000} placeholder="Что хотите предложить или уточнить?" className="prisma-glass-control min-h-24 w-full rounded-lg border px-3 py-2 text-sm"/>
        <button className="rounded-lg bg-[var(--primary)] px-3 py-2 text-xs font-semibold text-[var(--primary-foreground)]">Отправить запрос</button>
       </form>
      </details>
    ):null}

    {user && x.seller_id!==user.id?(
      <details className="prisma-glass-surface mt-2 rounded-xl border">
       <summary className="prisma-glass-hover cursor-pointer list-none px-3 py-2 text-xs font-semibold">🤝 Предложить цену</summary>
       <form action="/api/market" method="post" className="space-y-2 border-t p-3">
        <input type="hidden" name="action" value="offer_create"/><input type="hidden" name="listing_id" value={x.id}/>{hiddenReturn}
        <input name="price" required maxLength={60} placeholder="Ваша цена, например 8 алмазов" className="prisma-glass-control w-full rounded-lg border px-3 py-2 text-sm"/>
        <input name="note" maxLength={300} placeholder="Заметка (необязательно)" className="prisma-glass-control w-full rounded-lg border px-3 py-2 text-sm"/>
        <button className="rounded-lg bg-[var(--primary)] px-3 py-2 text-xs font-semibold text-[var(--primary-foreground)]">Предложить</button>
       </form>
      </details>
    ):null}

    {user && x.seller_id===user.id?(
     <div className="mt-4 space-y-2">
      <details className="prisma-glass-surface prisma-glass-hover rounded-xl border">
       <summary className="cursor-pointer list-none px-3 py-2 text-xs font-semibold">Редактировать</summary>
       <form action="/api/market" method="post" className="grid gap-2 border-t p-3">
        <input type="hidden" name="action" value="edit"/><input type="hidden" name="listing_id" value={x.id}/>
        <input type="hidden" name="return_q" value={q}/><input type="hidden" name="return_kind" value={kind}/>
        <select name="kind" defaultValue={x.kind} required className="prisma-glass-control rounded-lg border px-3 py-2 text-sm"><option value="SELL">Продам</option><option value="BUY">Куплю</option><option value="TRADE">Обмен</option><option value="SERVICE">Помогу / услуга</option><option value="OTHER">Другое</option></select>
        <input name="title" required minLength={3} maxLength={100} defaultValue={x.title} className="prisma-glass-control rounded-lg border px-3 py-2 text-sm"/>
        <textarea name="description" maxLength={1000} className="prisma-glass-control min-h-24 rounded-lg border px-3 py-2 text-sm" placeholder="Что предлагаете / ищете">{x.description||""}</textarea>
        <input name="price_text" maxLength={200} defaultValue={x.price_text||""} placeholder="Цена / вознаграждение / условия" className="prisma-glass-control rounded-lg border px-3 py-2 text-sm"/>
        <input name="terms" maxLength={500} defaultValue={x.terms||""} placeholder="Дополнительные условия" className="prisma-glass-control rounded-lg border px-3 py-2 text-sm"/>
        <select name="expiry_days" defaultValue={x.expires_at ? "keep" : "0"} className="prisma-glass-control rounded-lg border px-3 py-2 text-sm">
          {x.expires_at ? <option value="keep">Оставить текущий срок</option> : null}
          <option value="0">Без срока</option><option value="1">На 1 день</option><option value="3">На 3 дня</option>
          <option value="7">На 7 дней</option><option value="14">На 14 дней</option><option value="30">На 30 дней</option>
        </select>
        <button className="rounded-lg bg-[var(--primary)] px-3 py-2 text-xs font-semibold text-[var(--primary-foreground)]">Сохранить изменения</button>
       </form>
      </details>
      <form action="/api/market" method="post">
       <input type="hidden" name="action" value="close"/><input type="hidden" name="listing_id" value={x.id}/>
       <input type="hidden" name="return_q" value={q}/><input type="hidden" name="return_kind" value={kind}/>
       <button className="prisma-glass-control prisma-glass-hover rounded-lg border px-3 py-2 text-xs font-semibold">Снять объявление</button>
      </form>
     </div>
    ):null}
   </Card>)}
   {!listings.length&&<EmptyState title="Объявлений нет" body="Создай первое объявление или измени фильтры."/>}
  </div>
 </div>;
}
