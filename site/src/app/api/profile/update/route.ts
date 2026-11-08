import { NextResponse } from "next/server";
import { isPublicModuleEnabled } from "@/lib/modules";
import { getCurrentUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_PROFILE_MUTATION_RPC } from "@prisma-eco/contracts";

function redirect(req:Request,target:string){
  return NextResponse.redirect(new URL(target,req.url),303);
}

export async function POST(req:Request){
  if (!(await isPublicModuleEnabled("players"))) {
    return redirect(req, "/app?error=module_disabled&module=players");
  }
  const user=await getCurrentUser();
  if(!user)return redirect(req,"/login");

  const form=await req.formData();
  const fullName=String(form.get("full_name")??"").trim();
  const locale=String(form.get("locale")??"ru").trim().toLowerCase();
  const links={
    website:String(form.get("website")??"").trim(),
    discord:String(form.get("discord")??"").trim(),
    youtube:String(form.get("youtube")??"").trim(),
    telegram:String(form.get("telegram")??"").trim(),
  };

  if(fullName.length<2||fullName.length>100||!["uk","ru","en"].includes(locale))
    return redirect(req,"/app/profile?error=invalid");

  const db=await createSupabaseServerClient();
  const {error}=await db.rpc(PARTICIPANT_PROFILE_MUTATION_RPC.update,{
    p_full_name:fullName,
    p_locale:locale,
    p_profile_links:links,
  });

  return redirect(req,error?"/app/profile?error="+encodeURIComponent(
    error.message==="INVALID_PROFILE_LINK_URL"?"Ссылки должны быть HTTPS и не длиннее 300 символов.":
    error.message==="INVALID_PROFILE_LINK_KEY"?"Указано недопустимое поле ссылки.":
    error.message==="PLAYER_ACCESS_REQUIRED"?"Профиль доступен только одобренным и допущенным к серверу участникам.":
    error.message==="INVALID_LOCALE"?"Выберите корректный язык.":
    "Не удалось сохранить профиль."
  ):"/app/profile?saved=1");
}
