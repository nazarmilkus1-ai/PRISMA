import { isPublicModuleEnabled } from "@/lib/modules";
import {NextResponse} from "next/server";
import {getPublicServerStatus} from "@/lib/data";
export async function GET(){if (!(await isPublicModuleEnabled("minecraft"))) return NextResponse.json({ok:false,error:"module_disabled"},{status:404,headers:{"Cache-Control":"no-store"}});const server=await getPublicServerStatus();return NextResponse.json({ok:true,server,generated_at:new Date().toISOString()},{headers:{"Cache-Control":"public, s-maxage=30, stale-while-revalidate=120"}});}
