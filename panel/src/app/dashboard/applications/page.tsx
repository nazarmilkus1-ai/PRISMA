import Link from "next/link";
import { requireAdmin } from "@/lib/require-admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Badge, Card, CardContent, CardHeader, CardTitle, EmptyState, Input, PageHeader } from "@prisma-eco/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";
import { formatDateTime } from "@prisma-eco/shared";

type ApplicationRow = {
  id: string;
  application_no: number | null;
  nickname: string;
  full_name: string;
  age: number;
  platform: string;
  discovery_source: string | null;
  created_at: string;
};

export default async function ApplicationsPage({ searchParams }: { searchParams: Promise<{ status?: string; q?: string }> }) {
  const admin = await requireAdmin("application.view");
  if (!admin) return null;

  const sp = await searchParams;
  const status = ["ALL", "PENDING", "ACCEPTED", "REJECTED"].includes(sp.status || "") ? sp.status! : "PENDING";
  const query = (sp.q || "").trim();

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.applications, {
    p_status: status,
    p_search: query,
    p_limit: 500,
  });
  const applications = Array.isArray(data) ? data as ApplicationRow[] : [];
  if (error) throw new Error("Не удалось загрузить заявки.");

  const label = status === "PENDING" ? "На рассмотрении" : status === "ACCEPTED" ? "Принятые" : status === "REJECTED" ? "Отклонённые" : "Все";
  return <div className="space-y-6">
    <PageHeader
      eyebrow="People"
      title="Заявки"
      description="Рассмотрение заявок через единый application workflow."
      actions={<Badge variant={status === "PENDING" ? "warning" : "secondary"}>{label}</Badge>}
    />
    <Card>
      <CardContent className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <form action="/dashboard/applications" className="flex w-full gap-2 md:max-w-xl">
          <Input name="q" defaultValue={query} placeholder="Поиск по нику, имени или номеру"/>
          <input type="hidden" name="status" value={status}/>
          <button type="submit" className="h-9 shrink-0 rounded-md border bg-background px-3 text-sm font-medium hover:bg-accent">Найти</button>
        </form>
        <div className="flex gap-1">
          {(["PENDING","ACCEPTED","REJECTED","ALL"] as const).map(s =>
            <Link
              key={s}
              href={"/dashboard/applications?status="+s}
              className={"inline-flex h-8 items-center rounded-md px-3 text-xs font-medium "+(s===status?"bg-accent text-foreground":"text-muted-foreground hover:bg-accent hover:text-foreground")}
            >
              {s==="PENDING"?"Ожидают":s==="ACCEPTED"?"Принятые":s==="REJECTED"?"Отклонённые":"Все"}
            </Link>
          )}
        </div>
      </CardContent>
    </Card>
    <Card className="overflow-hidden">
      <CardHeader><CardTitle>{applications.length} заявок</CardTitle></CardHeader>
      {applications.length ? <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/50 text-left text-xs text-muted-foreground">
            <tr><th className="px-4 py-3 font-medium">№</th><th className="px-4 py-3 font-medium">Игрок</th><th className="px-4 py-3 font-medium">Возраст</th><th className="px-4 py-3 font-medium">Платформа</th><th className="px-4 py-3 font-medium">Источник</th><th className="px-4 py-3 font-medium">Создана</th><th className="px-4 py-3"/></tr>
          </thead>
          <tbody className="divide-y">
            {applications.map((app) =>
              <tr key={app.id} className="hover:bg-muted/50">
                <td className="px-4 py-3 font-mono text-xs text-muted-foreground">#{app.application_no}</td>
                <td className="px-4 py-3"><Link href={"/dashboard/applications/"+app.id} className="font-medium hover:underline">{app.nickname}</Link><div className="mt-0.5 text-xs text-muted-foreground">{app.full_name}</div></td>
                <td className="px-4 py-3">{app.age}</td>
                <td className="px-4 py-3">{app.platform}</td>
                <td className="px-4 py-3 text-muted-foreground">{app.discovery_source || "—"}</td>
                <td className="px-4 py-3 text-xs text-muted-foreground">{formatDateTime(app.created_at)}</td>
                <td className="px-4 py-3 text-right"><Link href={"/dashboard/applications/"+app.id} className="text-xs font-medium hover:underline">Открыть →</Link></td>
              </tr>
            )}
          </tbody>
        </table>
      </div> : <EmptyState icon="applications" title="Заявок нет" description="По текущему фильтру заявки отсутствуют."/>}
    </Card>
  </div>;
}
