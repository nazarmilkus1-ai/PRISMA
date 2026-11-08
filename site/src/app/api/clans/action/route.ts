import {NextResponse} from "next/server";
import {getCurrentUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {PARTICIPANT_CLAN_MUTATION_RPC} from "@prisma-eco/contracts";
import {isPublicModuleEnabled} from "@/lib/modules";

const ERRORS:Record<string,string>={
 USER_NOT_LINKED:"Профиль PRISMA не связан с текущим аккаунтом.",
 USER_NOT_APPROVED:"Действие доступно только одобренным участникам.",
 PLAYER_ACCESS_REQUIRED:"Действие доступно только одобренным и допущенным к серверу участникам.",
 CLAN_NOT_FOUND:"Клан не найден.",
 CLAN_NOT_FOUND_OR_CLOSED:"Клан не найден или закрыт для свободного вступления.",
 CLAN_NOT_OPEN:"Этот клан не принимает новых участников.",
 ALREADY_IN_CLAN:"Вы уже состоите в клане.",
 USER_ALREADY_IN_CLAN:"Вы уже состоите в клане.",
 NO_CLAN:"Вы не состоите в клане.",
 OWNER_CANNOT_LEAVE:"Владелец не может выйти из клана.",
 NO_CLAN_PERMISSION:"Недостаточно прав в клане.",
 OWNER_ONLY:"Это действие доступно только владельцу клана.",
 TARGET_REQUIRED:"Укажите игрока.",
 TARGET_INVALID_ROLE:"Для этого действия требуется участник с подходящей ролью.",
 TARGET_NOT_IN_CLAN:"Игрок не состоит в вашем клане.",
 PLAYER_NOT_FOUND:"Игрок не найден.",
 PLAYER_ALREADY_IN_CLAN:"Игрок уже состоит в клане.",
 CANNOT_INVITE_SELF:"Нельзя пригласить самого себя.",
 INVITE_ALREADY_EXISTS:"Этому игроку уже отправлено приглашение.",
 INVITE_NOT_FOUND:"Приглашение не найдено или уже недействительно.",
 CANNOT_KICK:"Этого игрока нельзя исключить.",
 INVALID_ACTION:"Недопустимое действие.",
 INVALID_VILLAGE:"Некорректные данные территории.",
 INVALID_ANNOUNCEMENT:"Заголовок: 3–120 символов, текст: 3–3000 символов.",
 INVALID_ROLE:"Выберите корректную роль.",
 ROLE_UNCHANGED:"У игрока уже установлена эта роль.",
 CANNOT_MANAGE_SELF:"Нельзя изменять собственную роль.",
 INVALID_CLAN_NAME:"Название клана должно содержать 2–32 символа.",
 INVALID_CLAN_TAG:"Тег должен содержать 2–6 латинских букв или цифр.",
 INVALID_CLAN_DESCRIPTION:"Описание клана: максимум 500 символов.",
 INVALID_CLAN_TYPE:"Выберите корректный тип клана.",
 CLAN_NAME_TAKEN:"Такое название клана уже занято.",
 CLAN_TAG_TAKEN:"Такой тег клана уже занят.",
 ANNOUNCEMENT_NOT_FOUND:"Объявление не найдено.",
 WAR_ALREADY_ACTIVE:"У вашего клана уже есть активная война.",
 WAR_NOT_FOUND:"Война не найдена.",
 WAR_NOT_ACTIVE:"Эта война уже завершена или отменена.",
 WAR_NOT_PENDING:"Этот вызов уже обработан.",
 WAR_NOT_SCHEDULED:"Эта война ещё не запланирована.",
 INVALID_SCORE:"Укажите неотрицательный целочисленный счёт.",
 CLAN_CREATE_RETRY:"Не удалось создать клан. Повторите попытку.",
 UNKNOWN_ACTION:"Неизвестное действие.",
 forbidden:"Действие недоступно для вашего аккаунта.",
};

const fail=(req:Request,msg:string)=>NextResponse.redirect(new URL("/app/clan?error="+encodeURIComponent(ERRORS[msg]??msg),req.url),303);

export async function POST(req:Request){
 const user=await getCurrentUser();
 if(!user)return NextResponse.redirect(new URL("/login",req.url),303);
 if(user.is_banned||user.status!=="ACCEPTED")return fail(req,"forbidden");
 if(!(await isPublicModuleEnabled("clans")))return NextResponse.redirect(new URL("/app?error=module_disabled&module=clans",req.url),303);

 const form=await req.formData();
 const action=String(form.get("action")||"");
 const target=String(form.get("target")||"").trim();
 const inviteId=String(form.get("invite_id")||"");
 const villageId=String(form.get("village_id")||"");
 const role=String(form.get("role")||"").trim().toLowerCase();
 const db=await createSupabaseServerClient();

 try{
  if(action==="join"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.join,{p_clan_id:target});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"CLAN_NOT_FOUND");
  }else if(action==="leave"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.leave);
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"NO_CLAN");
  }else if(action==="invite"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.invite,{p_target_nickname:target});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"CLAN_NOT_FOUND");
  }else if(action==="accept"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.acceptInvite,{p_invite_id:inviteId});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"CLAN_NOT_FOUND");
  }else if(action==="cancel_invite"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.cancelInvite,{p_invite_id:inviteId});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"INVITE_NOT_FOUND");
  }else if(action==="decline"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.declineInvite,{p_invite_id:inviteId});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"CLAN_NOT_FOUND");
  }else if(action==="set_role"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.setRole,{p_target_nickname:target,p_role:role});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"NO_CLAN_PERMISSION");
  }else if(["kick","promote","demote","transfer","disband"].includes(action)){
   if(action==="disband"&&String(form.get("confirm")||"")!=="yes")throw new Error("INVALID_ACTION");
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.action,{p_action:action.toUpperCase(),p_target_nickname:target||null});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"NO_CLAN_PERMISSION");
  }else if(action==="clan_update"){
   const name=String(form.get("name")||"").trim();
   const tag=String(form.get("tag")||"").trim();
   const description=String(form.get("description")||"");
   const type=String(form.get("type")||"open");
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.update,{p_name:name,p_tag:tag,p_description:description,p_type:type});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"NO_CLAN_PERMISSION");
  }else if(action==="announcement_create"){
   const title=String(form.get("title")||"").trim();
   const body=String(form.get("body")||"").trim();
   if(title.length<3||title.length>120||body.length<3||body.length>3000)throw new Error("INVALID_ANNOUNCEMENT");
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.createAnnouncement,{p_title:title,p_body:body});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"NO_CLAN_PERMISSION");
  }else if(action==="announcement_delete"){
   const announcementId=String(form.get("announcement_id")||"").trim();
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.deleteAnnouncement,{p_announcement_id:announcementId});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"ANNOUNCEMENT_NOT_FOUND");
  }else if(action==="war_accept"||action==="war_decline"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.respondWar,{p_war_id:target,p_action:action==="war_accept"?"ACCEPT":"DECLINE"});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"WAR_NOT_PENDING");
  }else if(action==="war_start"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.startWar,{p_war_id:target});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"WAR_NOT_SCHEDULED");
  }else if(action==="war_finish"){
   const scoreA=Number(form.get("score_a"));
   const scoreB=Number(form.get("score_b"));
   if(!Number.isInteger(scoreA)||!Number.isInteger(scoreB)||scoreA<0||scoreB<0)throw new Error("INVALID_SCORE");
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.finishWar,{p_war_id:target,p_score_a:scoreA,p_score_b:scoreB});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"WAR_NOT_ACTIVE");
  }else if(action==="war"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.createWar,{p_target:target});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"CLAN_NOT_FOUND");
  }else if(action==="war_cancel"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.cancelWar,{p_war_id:target});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"WAR_NOT_FOUND");
  }else if(action==="village_create"){
   const name=String(form.get("name")||"").trim();
   const world=String(form.get("world")||"world").trim();
   const x=Number(form.get("x"));
   const y=Number(form.get("y")||64);
   const z=Number(form.get("z"));
   const radius=Number(form.get("radius")||48);
   if(name.length<2||name.length>80||!world||!Number.isFinite(x)||!Number.isFinite(y)||!Number.isFinite(z)||!Number.isFinite(radius)||radius<8||radius>512)throw new Error("INVALID_VILLAGE");
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.createVillage,{p_name:name,p_world:world,p_x:x,p_y:y,p_z:z,p_radius:Math.round(radius)});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"INVALID_VILLAGE");
  }else if(action==="village_delete"){
   const{data,error}=await db.rpc(PARTICIPANT_CLAN_MUTATION_RPC.deleteVillage,{p_village_id:villageId});
   if(error)throw error;
   if(!data||data.success===false)throw new Error(data?.error||"CLAN_NOT_FOUND");
  }else{
   throw new Error("INVALID_ACTION");
  }
 }catch(error:unknown){
  return fail(req,String((error as{message?:string})?.message||"action_failed"));
 }
 return NextResponse.redirect(new URL("/app/clan",req.url),303);
}
