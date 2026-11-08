import { isPublicModuleEnabled } from "@/lib/modules";
import {NextResponse} from "next/server";
import {z} from "zod";
import {requireUser} from "@/lib/auth";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {PARTICIPANT_REPORT_MUTATION_RPC} from "@prisma-eco/contracts";

const Schema=z.object({
  type:z.enum(["PLAYER","BUG","SERVER"]),
  target_nickname:z.string().trim().max(32).optional().default(""),
  description:z.string().trim().min(3).max(4000)
});

async function moduleDisabledResponse(request: Request) {
  return NextResponse.redirect(new URL("/app?error=module_disabled&module=reports", request.url), 303);
}

export async function POST(request:Request){
  if (!(await isPublicModuleEnabled("reports"))) return moduleDisabledResponse(request);
  const user=await requireUser();
  if(user.is_banned)return NextResponse.redirect(new URL("/app/reports?error=banned",request.url));
  const parsed=Schema.safeParse(Object.fromEntries((await request.formData()).entries()));
  if(!parsed.success)return NextResponse.redirect(new URL("/app/reports?error=invalid",request.url));
  const db=await createSupabaseServerClient();
  const {data,error}=await db.rpc(PARTICIPANT_REPORT_MUTATION_RPC.create,{
    p_type:parsed.data.type,
    p_target_nickname:parsed.data.type==="PLAYER"?parsed.data.target_nickname:null,
    p_description:parsed.data.description
  });
  if(error||data?.success!==true){
    const code=error?.message||data?.error||"";
    const message=
      code==="PLAYER_ACCESS_REQUIRED"?"Отправлять репорты могут только одобренные и допущенные к серверу участники.":
      code==="DUPLICATE_OPEN_REPORT"?"У вас уже есть открытый репорт на этого игрока.":
      code==="TARGET_INVALID"?"Укажите действующего участника PRISMA.":
      code==="TARGET_REQUIRED"?"Укажите игрока для этого типа репорта.":
      code==="INVALID_REASON"?"Описание репорта должно содержать 3–4000 символов.":
      "Не удалось создать репорт.";
    return NextResponse.redirect(new URL("/app/reports?error="+encodeURIComponent(message),request.url));
  }
  return NextResponse.redirect(new URL("/app/reports?created=1",request.url));
}
