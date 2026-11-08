import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import {notFound} from "next/navigation";
import {getPublicClans} from "@/lib/data";
export const metadata={title:"Клан"};
export default async function ClanTagPage({params}:{params:Promise<{tag:string}>}){
  await requireModuleMember("clans");const {tag}=await params;const clans=await getPublicClans(200);const clan=clans.find((x:any)=>String(x.tag).toLowerCase()===decodeURIComponent(tag).toLowerCase());if(!clan)return notFound();
 const Page=(await import("@/app/clans/[id]/page")).default;
 return Page({params:Promise.resolve({id:clan.id})} as any);
}
