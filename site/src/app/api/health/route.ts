import { NextResponse } from "next/server";
import { PUBLIC_RPC } from "@prisma-eco/contracts";
import { createSupabasePublicClient } from "@/lib/supabase/public";

export async function GET() {
  const required = ["NEXT_PUBLIC_SUPABASE_URL","NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"];
  const missing = required.filter((key) => !process.env[key]);
  if (missing.length) return NextResponse.json({ ok: false, missing }, { status: 503, headers: { "Cache-Control": "no-store" } });

  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.serverStatus);
  if(error) return NextResponse.json({ok:false,database:false},{status:503,headers:{"Cache-Control":"no-store"}});
  return NextResponse.json({ok:true,database:true,server_node:Boolean(data),timestamp:new Date().toISOString()},{headers:{"Cache-Control":"no-store"}});
}
