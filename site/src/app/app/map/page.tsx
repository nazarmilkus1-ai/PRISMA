import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import {getMapData} from "@/lib/data";
import {PageHeader} from "@prisma-eco/ui";
import {WorldMap} from "@/components/WorldMap";

export const metadata={title:"Карта"};

export default async function ParticipantMapPage(){
  await requireModuleUser("map");
 const {markers,villages}=await getMapData();
 return <div className="space-y-5">
  <PageHeader eyebrow="СЕРВЕР" title="Карта" description="Интерактивная карта PRISMA: точки, города и территории." actions={<Link href="/server#map" className="rounded-xl border px-4 py-2.5 text-sm">Версия сервера →</Link>}/>
  <WorldMap markers={markers as any} villages={villages as any}/>
 </div>;
}
