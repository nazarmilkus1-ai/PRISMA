import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card } from "@/components/Card";
import { StatusBadge } from "@/components/StatusBadge";
import { WorldMap } from "@/components/WorldMap";
import { getMapData, getPublicServerStatus } from "@/lib/data";

export const metadata={title:"Сервер"};

export default async function ServerPage(){
  await requireModule("minecraft");
  const server=await getPublicServerStatus();
  const {markers,villages}=await getMapData();

  return <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-[var(--primary)]">MINECRAFT</p><h1 className="mt-1 text-3xl font-semibold">Сервер PRISMA</h1><p className="mt-1 text-sm text-[var(--muted-foreground)]">Сервер и карта мира теперь находятся в одном месте.</p></div><StatusBadge online={server.online}>{server.online?"Сервер онлайн":"Сервер офлайн"}</StatusBadge></div>

    <Card className="prisma-glass-surface mt-5 p-5">
      <p className="text-xs text-[var(--muted-foreground)]">Статус сервера</p>
      <p className="mt-2 text-2xl font-semibold">{server.online ? "Онлайн" : "Офлайн"}</p>
      <p className="mt-2 text-sm text-[var(--muted-foreground)]">Публичная часть PRISMA показывает только доступность сервера. Адрес, версия и список/количество игроков доступны участникам в кабинете.</p>
    </Card>

    <Card className="prisma-glass-surface mt-4 p-5"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-xs text-[var(--muted-foreground)]">Подключение</p><p className="mt-1 font-semibold">Адрес доступен участникам PRISMA</p><p className="mt-1 text-xs text-[var(--muted-foreground)]">Публичная страница не показывает сетевой адрес сервера.</p></div><Link href="/app/minecraft" className="prisma-glass-control prisma-glass-hover rounded-xl border px-4 py-2.5 text-sm font-medium">Открыть кабинет →</Link></div></Card>

    <section id="map" className="mt-6"><div className="mb-3 flex items-end justify-between gap-3"><div><h2 className="text-xl font-semibold">Карта мира</h2><p className="mt-1 text-sm text-[var(--muted-foreground)]">Кланы, события и важные точки прямо внутри страницы сервера.</p></div><Link href="/app/history" className="text-xs font-semibold text-[var(--primary)]">Аналитика →</Link></div><WorldMap markers={markers as any} villages={villages as any}/></section>
    <p className="mt-3 text-xs text-[var(--muted-foreground)]">Статус сервера обновляется автоматически.</p>
  </div>;
}
