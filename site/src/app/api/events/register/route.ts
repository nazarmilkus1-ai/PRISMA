import { isPublicModuleEnabled } from "@/lib/modules";
import {NextResponse} from "next/server";
import {getCurrentUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {PARTICIPANT_EVENT_MUTATION_RPC} from "@prisma-eco/contracts";

const ERRORS:Record<string,string>={
  USER_NOT_LINKED:"Профиль PRISMA не связан с текущим аккаунтом.",
  PLAYER_ACCESS_REQUIRED:"Регистрация доступна только одобренным участникам.",
  EVENT_NOT_FOUND:"Событие не найдено.",
  EVENT_NOT_OPEN:"Регистрация на это событие закрыта.",
  REGISTRATION_CLOSED:"Регистрация уже закрыта.",
  EVENT_FULL:"Свободных мест больше нет.",
  REGISTRATION_NOT_FOUND:"Вы не зарегистрированы на это событие.",
  EVENT_ALREADY_STARTED:"Отменить регистрацию после начала события нельзя.",
  INVALID_STATUS_TRANSITION:"Нельзя перевести событие в этот статус.",
  MAX_BELOW_CURRENT_PARTICIPANTS:"Лимит участников не может быть меньше уже зарегистрированного состава.",
};

async function moduleDisabledResponse(request: Request) {
  return NextResponse.redirect(new URL("/app?error=module_disabled&module=events", request.url), 303);
}

export async function POST(req:Request){
  if (!(await isPublicModuleEnabled("events"))) return moduleDisabledResponse(req);
  const user=await getCurrentUser();
  if(!user)return NextResponse.redirect(new URL("/login",req.url),303);
  const failBack=new URL("/events",req.url);
  if(user.status!=="ACCEPTED"||user.is_banned||!user.is_whitelisted){
    failBack.searchParams.set("error","forbidden");
    return NextResponse.redirect(failBack,303);
  }

  const form=await req.formData();
  const eventId=String(form.get("event_id")||"").trim();
  const slug=String(form.get("slug")||"").trim();
  const action=String(form.get("action")||"register");
  if(!eventId || !slug || !/^[A-Za-z0-9._-]{1,120}$/.test(slug) || (action!=="register"&&action!=="unregister")){
    const back=new URL("/events",req.url);
    back.searchParams.set("error","invalid");
    return NextResponse.redirect(back,303);
  }

  const db=await createSupabaseServerClient();
  const {error}=await db.rpc(
    action==="register"?PARTICIPANT_EVENT_MUTATION_RPC.register:PARTICIPANT_EVENT_MUTATION_RPC.unregister,
    {p_event_id:eventId},
  );

  const back=new URL("/events/"+encodeURIComponent(slug),req.url);
  back.searchParams.set(error?"error":"updated",error?(ERRORS[error.message]||"Не удалось изменить регистрацию."):"1");
  return NextResponse.redirect(back,303);
}
