import { requireAdminContext } from "@/lib/require-admin";
import { getStaffModuleStates } from "@/lib/modules";
import { MODULE_IDS, MODULE_METADATA, type ModuleId, type StaffModuleState } from "@prisma-eco/contracts";
import { Card, CardContent, CardHeader, CardTitle, PageHeader } from "@prisma-eco/ui";
import { ModulesPanel } from "@/components/ModulesPanel";

const PROTECTED = new Set<ModuleId>(
  MODULE_IDS.filter((id) => MODULE_METADATA[id].runtimeToggleProtected),
);

export default async function ModulesPage() {
  const context = await requireAdminContext("modules.view");
  if (!context) return null;

  const result = await getStaffModuleStates();

  const stateById = new Map<string, StaffModuleState>(
    result.states.map((state) => [state.module_id, state]),
  );

  const modules = MODULE_IDS.map((id) => ({
    id,
    title: MODULE_METADATA[id].title,
    protected: PROTECTED.has(id),
    ...(stateById.get(id) ?? {
      module_id: id,
      enabled: true,
      reason: null,
      updated_by: null,
      updated_at: new Date(0).toISOString(),
    }),
  }));

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Система"
        title="Модули"
        description="Центральное runtime-управление доменами PRISMA. Изменения проходят RBAC и audit log."
      />

      {result.error ? (
        <Card>
          <CardHeader><CardTitle>Состояние недоступно</CardTitle></CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">{result.error}</p>
          </CardContent>
        </Card>
      ) : (
        <ModulesPanel
          modules={modules}
          canManage={context.permissions.has("*") || context.permissions.has("modules.manage")}
        />
      )}
    </div>
  );
}
