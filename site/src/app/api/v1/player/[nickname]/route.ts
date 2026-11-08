import { isPublicModuleEnabled } from "@/lib/modules";
import {NextResponse} from "next/server";
import {getCurrentUser} from "@/lib/auth";
import {getPlayerProfile} from "@/lib/data";
export async function GET(req:Request,{params}:{params:Promise<{nickname:string}>}){if (!(await isPublicModuleEnabled("players"))) return NextResponse.json({ok:false,error:"module_disabled"},{status:404,headers:{"Cache-Control":"no-store"}});const u=await getCurrentUser();if(!u||u.status!=="ACCEPTED"||u.is_banned)return NextResponse.json({ok:false,error:"member_only"},{status:403});const{nickname}=await params;const player=await getPlayerProfile(decodeURIComponent(nickname));if(!player)return NextResponse.json({ok:false,error:"not_found"},{status:404});return NextResponse.json({ok:true,player,generated_at:new Date().toISOString()});}
