import { isPublicModuleEnabled } from "@/lib/modules";
import { PARTICIPANT_MARKET_MUTATION_RPC, PARTICIPANT_MARKET_RPC } from "@prisma-eco/contracts";
import {NextResponse} from "next/server";
import {getCurrentUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";

const KINDS=new Set(["SELL","BUY","TRADE","SERVICE","OTHER"]);
const EXPIRY_DAYS=new Set(["0","1","3","7","14","30"]);
const ERRORS:Record<string,string>={
 LISTING_NOT_FOUND:"Объявление уже снято, не существует или вам не принадлежит.",
 INVALID_LISTING:"Проверьте тип и длину полей объявления.",
 INVALID_INQUIRY:"Сообщение должно содержать 3–1000 символов.",
 INVALID_INQUIRY_RESPONSE:"Ответ должен содержать 3–1500 символов.",
 SELF_LISTING_FORBIDDEN:"Нельзя отправить запрос на собственное объявление.",
 INQUIRY_ALREADY_OPEN:"По этому объявлению у вас уже есть открытый запрос.",
 INQUIRY_NOT_FOUND:"Запрос не найден или уже закрыт.",
 INQUIRY_FORBIDDEN:"У вас нет доступа к этому запросу.",
 INQUIRY_CLOSED:"Этот запрос уже закрыт.",
 INQUIRY_ALREADY_ANSWERED:"На этот запрос уже ответили.",
 INVALID_OFFER:"Цена — от 1 до 60 символов, заметка — до 300.",
 OFFER_ALREADY_OPEN:"По этому объявлению у вас уже есть активное предложение.",
 OFFER_NOT_FOUND:"Предложение не найдено или уже закрыто.",
 OFFER_FORBIDDEN:"Ответить на это предложение может только другая сторона.",
 OFFER_CLOSED:"Это предложение уже обработано.",
 OFFER_EXPIRED:"Время на ответ (72 часа) истекло. Предложите цену заново.",
 OFFER_MAX_ROUNDS:"Достигнут лимит из 6 раундов торга: договоритесь лично.",
};

function redirectMarket(req:Request,key:string,value:string,returnQ:string,returnKind:string){
 const url=new URL("/app/market",req.url);
 if(returnQ)url.searchParams.set("q",returnQ);
 if(returnKind)url.searchParams.set("kind",returnKind);
 url.searchParams.set(key,value);
 return NextResponse.redirect(url,303);
}

async function moduleDisabledResponse(request: Request) {
  return NextResponse.redirect(new URL("/app?error=module_disabled&module=market", request.url), 303);
}

export async function POST(req:Request){
  if (!(await isPublicModuleEnabled("market"))) return moduleDisabledResponse(req);
 const user=await getCurrentUser();
 if(!user)return NextResponse.redirect(new URL("/login",req.url),303);
 if(user.status!=="ACCEPTED"||user.is_banned||!user.is_whitelisted)return redirectMarket(req,"error","forbidden","","");

 const form=await req.formData();
 const action=String(form.get("action")||"create");
 const returnQ=String(form.get("return_q")||"").trim();
 const returnKind=String(form.get("return_kind")||"").trim();

 if(action==="offer_create"){
  const listingId=String(form.get("listing_id")||"").trim();
  const price=String(form.get("price")||"").trim();
  const note=String(form.get("note")||"").trim();
  if(!listingId||price.length<1||price.length>60||note.length>300)return redirectMarket(req,"error",ERRORS.INVALID_OFFER,returnQ,returnKind);
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.createOffer,{p_listing_id:listingId,p_price:price,p_note:note||null});
  return redirectMarket(req,error?"error":"offer_sent",error?(ERRORS[error.message]||"Не удалось отправить предложение."):"1",returnQ,returnKind);
 }

 if(action==="offer_respond"){
  const offerId=String(form.get("offer_id")||"").trim();
  const answer=String(form.get("answer")||"").trim();
  const price=String(form.get("price")||"").trim();
  const note=String(form.get("note")||"").trim();
  if(!offerId||!["accept","reject","counter"].includes(answer)||(answer==="counter"&&(price.length<1||price.length>60||note.length>300)))return redirectMarket(req,"error",ERRORS.INVALID_OFFER,returnQ,returnKind);
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.respondOffer,{p_offer_id:offerId,p_action:answer,p_price:answer==="counter"?price:null,p_note:answer==="counter"?(note||null):null});
  return redirectMarket(req,error?"error":"offer_updated",error?(ERRORS[error.message]||"Не удалось ответить на предложение."):"1",returnQ,returnKind);
 }

 if(action==="offer_withdraw"){
  const offerId=String(form.get("offer_id")||"").trim();
  if(!offerId)return redirectMarket(req,"error",ERRORS.OFFER_NOT_FOUND,returnQ,returnKind);
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.withdrawOffer,{p_offer_id:offerId});
  return redirectMarket(req,error?"error":"offer_updated",error?(ERRORS[error.message]||"Не удалось отозвать предложение."):"1",returnQ,returnKind);
 }

 if(action==="inquiry_create"){
  const listingId=String(form.get("listing_id")||"").trim();
  const message=String(form.get("message")||"").trim();
  if(!listingId||message.length<3||message.length>1000)return redirectMarket(req,"error",ERRORS.INVALID_INQUIRY,returnQ,returnKind);
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.createInquiry,{p_listing_id:listingId,p_message:message});
  return redirectMarket(req,error?"error":"inquiry_sent",error?(ERRORS[error.message]||"Не удалось отправить запрос."):"1",returnQ,returnKind);
 }

 if(action==="inquiry_response"){
  const inquiryId=String(form.get("inquiry_id")||"").trim();
  const response=String(form.get("response")||"").trim();
  if(!inquiryId||response.length<3||response.length>1500)return redirectMarket(req,"error",ERRORS.INVALID_INQUIRY_RESPONSE,returnQ,returnKind);
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.respondInquiry,{p_inquiry_id:inquiryId,p_response:response});
  return redirectMarket(req,error?"error":"inquiry_updated",error?(ERRORS[error.message]||"Не удалось ответить на запрос."):"1",returnQ,returnKind);
 }

 if(action==="inquiry_close"){
  const inquiryId=String(form.get("inquiry_id")||"").trim();
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.closeInquiry,{p_inquiry_id:inquiryId});
  return redirectMarket(req,error?"error":"inquiry_closed",error?(ERRORS[error.message]||"Не удалось закрыть запрос."):"1",returnQ,returnKind);
 }

 if(action==="close"){
  const listingId=String(form.get("listing_id")||"").trim();
  const db=await createSupabaseServerClient();
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.closeListing,{p_listing_id:listingId});
  return redirectMarket(req,error?"error":"closed",error?(ERRORS[error.message]||"Не удалось снять объявление."):"1",returnQ,returnKind);
 }

 if(action==="edit"){
  const listingId=String(form.get("listing_id")||"").trim();
  const kind=String(form.get("kind")||"").trim().toUpperCase();
  const title=String(form.get("title")||"").trim();
  const description=String(form.get("description")||"").trim();
  const priceText=String(form.get("price_text")||"").trim();
  const terms=String(form.get("terms")||"").trim();
  const expiryDays=String(form.get("expiry_days")||"keep").trim();

  if(!listingId||!KINDS.has(kind)||!new Set([...EXPIRY_DAYS,"keep"]).has(expiryDays)||title.length<3||title.length>100||description.length>1000||priceText.length>200||terms.length>500){
   return redirectMarket(req,"error",ERRORS.INVALID_LISTING,returnQ,returnKind);
  }

  const db=await createSupabaseServerClient();
  let expiresAt:string|null=null;
  if(expiryDays==="keep"){
   const{data:current}=await db.rpc(PARTICIPANT_MARKET_RPC.listing,{p_listing_id:listingId});
   if(!current||typeof current!=="object"){
    return redirectMarket(req,"error",ERRORS.LISTING_NOT_FOUND,returnQ,returnKind);
   }
   expiresAt=(current as any).expires_at??null;
  }else{
   expiresAt=expiryDays==="0"?null:new Date(Date.now()+Number(expiryDays)*86400000).toISOString();
  }
  const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.updateListing,{
   p_listing_id:listingId,p_kind:kind,p_title:title,p_description:description||null,p_price_text:priceText||null,p_terms:terms||null,p_expires_at:expiresAt,
  });
  return redirectMarket(req,error?"error":"updated",error?(ERRORS[error.message]||"Не удалось обновить объявление."):"1",returnQ,returnKind);
 }

 const kind=String(form.get("kind")||"OTHER").trim().toUpperCase();
 const title=String(form.get("title")||"").trim();
 const description=String(form.get("description")||"").trim();
 const priceText=String(form.get("price_text")||"").trim();
 const terms=String(form.get("terms")||"").trim();
 const expiryDays=String(form.get("expiry_days")||"0").trim();

 if(!KINDS.has(kind)||!EXPIRY_DAYS.has(expiryDays)||title.length<3||title.length>100||description.length>1000||priceText.length>200||terms.length>500){
  return redirectMarket(req,"error",ERRORS.INVALID_LISTING,returnQ,returnKind);
 }

 const db=await createSupabaseServerClient();
 const expiresAt=expiryDays==="0"?null:new Date(Date.now()+Number(expiryDays)*86400000).toISOString();
 const{error}=await db.rpc(PARTICIPANT_MARKET_MUTATION_RPC.createListing,{
  p_kind:kind,
  p_title:title,
  p_description:description||null,
  p_price_text:priceText||null,
  p_terms:terms||null,
  p_expires_at:expiresAt,
 });

 return redirectMarket(req,error?"error":"created",error?(ERRORS[error.message]||"Не удалось опубликовать объявление."):"1",returnQ,returnKind);
}
