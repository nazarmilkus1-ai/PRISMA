import {isPublicModuleEnabled} from "@/lib/modules";
import {NextResponse} from "next/server";
import {getCurrentUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {PARTICIPANT_SOCIAL_MUTATION_RPC} from "@prisma-eco/contracts";

const ERRORS:Record<string,string>={
 TARGET_NOT_FOUND:"Игрок не найден.",
 SELF_TARGET_FORBIDDEN:"Нельзя выбрать самого себя.",
 ALREADY_MARRIED:"Один из участников уже состоит в браке.",
 INCOMING_MARRIAGE_REQUEST_EXISTS:"У этого игрока уже есть входящий запрос от вас.",
 MARRIAGE_REQUEST_ALREADY_SENT:"Запрос на брак уже отправлен.",
 MARRIAGE_REQUEST_NOT_FOUND:"Запрос на брак не найден или уже обработан.",
 INCOMING_RELATIONSHIP_REQUEST_EXISTS:"У этого игрока уже есть входящий запрос от вас.",
 ALREADY_IN_RELATIONSHIP:"Один из участников уже состоит в связи.",
 RELATIONSHIP_REQUEST_ALREADY_SENT:"Запрос на связь уже отправлен.",
 RELATIONSHIP_REQUEST_NOT_FOUND:"Запрос на связь не найден или уже обработан.",
 SOCIAL_REQUEST_FORBIDDEN:"У вас нет прав на это действие с запросом.",
 NO_ACTIVE_MARRIAGE:"Активного брака нет.",
 RELATIONSHIP_NOT_FOUND:"Активная связь не найдена.",
 USER_NOT_APPROVED:"Действие доступно только одобренным участникам.",
 USER_NOT_LINKED:"Профиль PRISMA не связан с текущим аккаунтом.",
 INVALID_SOCIAL_ACTION:"Недопустимое социальное действие.",
};

export async function POST(req:Request){
 if(!(await isPublicModuleEnabled("social")))return NextResponse.redirect(new URL("/app?error=module_disabled&module=social",req.url),303);
 const user=await getCurrentUser();
 if(!user)return NextResponse.redirect(new URL("/login",req.url),303);
 if(user.status!=="ACCEPTED"||user.is_banned)return NextResponse.redirect(new URL("/app/profile?social_error="+encodeURIComponent("forbidden"),req.url),303);

 const form=await req.formData();
 const action=String(form.get("action")||"").trim().toUpperCase();
 const target=String(form.get("target")||"").trim();
 const requestId=String(form.get("request_id")||"").trim();
 const rawReturnTo=String(form.get("return_to")||"").trim();
 const returnTo=/^\/players\/[A-Za-z0-9_.-]{1,32}$/.test(rawReturnTo) ? rawReturnTo : "/app/profile";
 const db=await createSupabaseServerClient();

 const{error}=await db.rpc(PARTICIPANT_SOCIAL_MUTATION_RPC.action,{
  p_action:action,
  p_target_nickname:target||null,
  p_request_id:requestId||null,
 });

 const targetUrl = error
  ? returnTo + "?social_error=" + encodeURIComponent(ERRORS[error.message] || "Не удалось выполнить действие.")
  : returnTo + "?social_done=1";

 return NextResponse.redirect(new URL(targetUrl, req.url), 303);
}
