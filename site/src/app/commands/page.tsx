import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import {MINECRAFT_AUTHENTICATION, MINECRAFT_CLAN_WAR_SUBCOMMANDS, MINECRAFT_COMMANDS, MINECRAFT_ROLES} from "@prisma-eco/contracts";
import {Card} from "@/components/Card";
import {SectionTitle} from "@/components/SitePrimitives";

const ACCESS_LABELS: Record<string,string> = {
  APPROVED:"Учасник",
  CLAN_MEMBER:"Учасник клану",
  CLAN_OFFICER:"Офицер / выше",
  CLAN_OWNER:"Власник / вище",
  STAFF:"Staff",
};

export const metadata={title:"Команды Minecraft"};

export default async function CommandsPage(){
  await requireModule("minecraft");
  return <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6">
    <SectionTitle eyebrow="MINECRAFT" title="Команды PRISMA" description="Единый список команд плагина, кланов, телепортаций и авторизации."/>
    <div className="mt-6 grid gap-4 lg:grid-cols-2">
      {MINECRAFT_COMMANDS.map((item:any)=>
        <Card key={item.command} className="p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <code className="text-base font-semibold">{item.command}</code>
              {item.aliases?.length ? <p className="mt-1 text-xs text-[var(--muted-foreground)]">Алиасы: {item.aliases.join(", ")}</p> : null}
            </div>
            <span className="prisma-glass-badge rounded-full px-2.5 py-1 text-[11px] font-semibold">{ACCESS_LABELS[item.access]??item.access}</span>
          </div>
          <p className="mt-3 text-sm text-[var(--muted-foreground)]">{item.description}</p>
          {item.subcommands?.length ? <div className="mt-4 space-y-2 border-t pt-4">
            {item.subcommands.map((row:any)=><div key={row[0]} className="flex flex-wrap items-center justify-between gap-2 text-sm">
              <code>{item.command} {row[0]}</code>
              <span className="text-xs text-[var(--muted-foreground)]">{row[1]} · {ACCESS_LABELS[row[2]]??row[2]}</span>
            </div>)}
          </div> : null}
        </Card>
      )}
    </div>
    <Card className="mt-6 p-5">
      <h2 className="font-semibold">Войны кланов</h2>
      <div className="mt-4 grid gap-2 sm:grid-cols-2">
        {MINECRAFT_CLAN_WAR_SUBCOMMANDS.map((row:any)=><div key={row[0]} className="prisma-glass-surface flex flex-wrap items-center justify-between gap-2 rounded-xl border p-3 text-sm">
          <code>/clan war {row[0]}</code>
          <span className="text-xs text-[var(--muted-foreground)]">{row[1]} · {ACCESS_LABELS[row[2]]??row[2]}</span>
        </div>)}
      </div>
    </Card>
    <Card className="mt-6 p-5">
      <h2 className="font-semibold">Роли PRISMA</h2>
      <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {MINECRAFT_ROLES.map((role:any)=><div key={role.id} className="prisma-glass-surface rounded-xl border p-3">
          <div className="flex items-center justify-between gap-3"><span className="font-semibold">[{role.label}] {role.name}</span><span className="text-xs text-[var(--muted-foreground)]">priority {role.priority}</span></div>
          <p className="mt-1 text-xs text-[var(--muted-foreground)]">{role.description}</p>
        </div>)}
      </div>
    </Card>
    <div className="mt-6 grid gap-4 lg:grid-cols-2">
      {MINECRAFT_AUTHENTICATION.map((auth:any)=><Card key={auth.platform} className="p-5">
        <div className="flex items-center justify-between gap-3"><h2 className="font-semibold">{auth.name}</h2><span className="prisma-glass-badge rounded-full px-2.5 py-1 text-[11px] font-semibold">{auth.platform}</span></div>
        <p className="mt-2 text-sm text-[var(--muted-foreground)]">{auth.description}</p>
        {auth.commands?.length ? <div className="mt-4 space-y-2 border-t pt-4">{auth.commands.map((row:any)=><div key={row[0]} className="flex flex-wrap items-center justify-between gap-2 text-sm"><code>{row[0]}</code><span className="text-xs text-[var(--muted-foreground)]">{row[1]}</span></div>)}</div> : <p className="prisma-glass-surface mt-4 rounded-xl border px-3 py-2 text-xs">Отдельных команд входа нет.</p>}
      </Card>)}
    </div>
  </div>;
}
