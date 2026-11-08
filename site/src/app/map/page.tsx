import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import {Card} from "@/components/Card";
import {getMapData} from "@/lib/data";
import {PageHeader} from "@prisma-eco/ui";
import {WorldMap} from "@/components/WorldMap";

export const metadata={title:"Карта"};

export default async function MapPage(){
  await requireModule("map");
 const {markers,villages}=await getMapData();
 return <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6">
  <PageHeader eyebrow="PRISMA WORLD" title="Карта мира" description="Спавн, города, территории кланов, события и важные точки без тяжёлого Dynmap." actions={<Link href="/server#map" className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-medium">Сервер →</Link>}/>
  <Card className="prisma-glass-surface mt-6 overflow-hidden"><WorldMap markers={markers as any} villages={villages as any}/></Card>
 </div>;
}
