import { isPublicModuleEnabled } from "@/lib/modules";
import {NextResponse} from "next/server";
import {getCurrentUser} from "@/lib/auth";
import {getPlayers} from "@/lib/data";
export async function GET(req:Request){if (!(await isPublicModuleEnabled("players"))) return NextResponse.json({ok:false,error:"module_disabled"},{status:404,headers:{"Cache-Control":"no-store"}});const u=await getCurrentUser();if(!u||u.status!=="ACCEPTED"||u.is_banned)return NextResponse.json({ok:false,error:"member_only"},{status:403});const q=new URL(req.url).searchParams.get("q")||"";return NextResponse.json({ok:true,players:await getPlayers(q,100),generated_at:new Date().toISOString()});}
