import { STAFF_ROLE_LABELS } from "@prisma-eco/contracts";
import { AdminsPanel } from "@/components/AdminsPanel";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdminContext } from "@/lib/require-admin";
import { STAFF_RPC } from "@prisma-eco/contracts";

type Role = {
  id: string;
  name: string;
  description: string | null;
  priority: number;
  parent_role_id: string | null;
};

type AdminRegistryEntry = {
  id: string;
  user_id: string;
  created_at: string;
  users: {
    id: string;
    telegram_id: number;
    telegram_username: string | null;
    first_name: string | null;
    full_name: string | null;
    minecraft_nickname: string | null;
    status: string | null;
    is_whitelisted: boolean;
    is_banned: boolean;
    is_muted: boolean;
    rating: number | null;
    activity_score: number | null;
    last_seen_at: string | null;
  };
  roles: Role & { parent_role_id?: string | null } | (Role & { parent_role_id?: string | null })[] | null;
};

type Permission = {
  id: string;
  key: string;
  description: string | null;
  category: string | null;
};

function rolePermissionsWithInheritance(
  role: Role,
  rolesById: Map<string, Role>,
  direct: Map<string, string[]>,
) {
  const effective: string[] = [];
  const seen = new Set<string>();
  let current: Role | undefined = role;

  while (current && !seen.has(current.id)) {
    seen.add(current.id);
    effective.push(...(direct.get(current.id) ?? []));
    current = current.parent_role_id ? rolesById.get(current.parent_role_id) : undefined;
  }

  return [...new Set(effective)].sort();
}

export default async function AdminsPage() {
  const context = await requireAdminContext("admin.view_audit");
  if (!context) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_RPC.adminRegistry);

  const payload = (data ?? {}) as {
    admins?: AdminRegistryEntry[];
    roles?: Role[];
    role_permissions?: { role_id: string; permission_id: string }[];
    permissions?: Permission[];
  };

  const admins = (payload.admins ?? []).map((admin) => ({
    id: admin.id,
    user_id: admin.user_id,
    created_at: admin.created_at,
    users: admin.users,
    roles: admin.roles ?? null,
  }));
  const roleList = payload.roles ?? [];
  const permissionList = payload.permissions ?? [];
  const rolesById = new Map(roleList.map((role) => [role.id, role]));

  const direct = new Map<string, string[]>();
  for (const role of roleList) direct.set(role.id, []);
  const permissionById = new Map(permissionList.map((permission) => [permission.id, permission.key]));

  for (const row of payload.role_permissions ?? []) {
    const key = permissionById.get(row.permission_id);
    if (!key) continue;
    direct.set(row.role_id, [...(direct.get(row.role_id) ?? []), key]);
  }

  const roleCards = roleList.map((role) => ({
    ...role,
    label: STAFF_ROLE_LABELS[role.name] ?? role.name,
    directPermissions: [...new Set(direct.get(role.id) ?? [])].sort(),
    effectivePermissions: rolePermissionsWithInheritance(role, rolesById, direct),
  }));

  const adminCounts = new Map<string, number>();
  for (const admin of admins) {
    const roleId = Array.isArray(admin.roles) ? admin.roles[0]?.id : admin.roles?.id;
    if (roleId) adminCounts.set(roleId, (adminCounts.get(roleId) ?? 0) + 1);
  }

  const canManage = context.permissions.has("*") || context.permissions.has("admin.manage");
  const loadError = error ? new Error(error.message) : null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl text-moon">Администраторы</h1>
        <p className="mt-1 max-w-3xl text-sm text-moon-dim">
          Профиль берётся из `users`, уровень доступа — из `admins → roles → permissions`.
          Керування ролями доступне лише з permission `admin.manage`.
        </p>
      </div>

      {loadError && (
        <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">
          Не удалось загрузить реестр: {loadError.message}
        </div>
      )}

      <AdminsPanel initialAdmins={admins} canManage={canManage} />

      <div className="rounded-xl border border-border bg-panel p-5">
        <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="font-medium text-moon">Матриця прав</h2>
            <p className="mt-1 text-sm text-moon-dim">Учитываются прямые разрешения роли и разрешения родительских ролей.</p>
          </div>
          <span className="text-xs text-moon-dim">{permissionList.length} разрешений · {roleList.length} ролей</span>
        </div>

        <div className="mt-4 overflow-x-auto">
          <div className="min-w-[720px] divide-y divide-border rounded-lg border border-border">
            {roleCards.map((role) => (
              <div key={role.id} className="grid grid-cols-[170px_90px_1fr] gap-3 bg-panel-raised/20 p-4">
                <div>
                  <p className="text-sm font-medium text-moon">{role.label}</p>
                  <p className="mt-1 text-[11px] text-moon-dim">
                    {adminCounts.get(role.id) ?? 0} адм.
                    {role.parent_role_id ? ` · наследует ${STAFF_ROLE_LABELS[rolesById.get(role.parent_role_id)?.name ?? ""] ?? "роль"}` : ""}
                  </p>
                </div>
                <div className="text-xs text-moon-dim">
                  <p>Прямые: {role.directPermissions.length}</p>
                  <p className="mt-1">Эффективные: {role.effectivePermissions.length}</p>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {role.effectivePermissions.map((key) => {
                    const inherited = !role.directPermissions.includes(key);
                    return (
                      <span
                        key={key}
                        className={
                          "rounded-md border px-2 py-1 font-mono text-[10px] " +
                          (inherited ? "border-border bg-muted/30 text-moon-dim" : "border-primary/30 bg-primary/10 text-moon")
                        }
                        title={inherited ? "Унаследовано" : "Прямое разрешение"}
                      >
                        {key}
                      </span>
                    );
                  })}
                </div>
              </div>
            ))}
            {roleCards.length === 0 && <p className="p-5 text-sm text-moon-dim">Роли не найдены.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
