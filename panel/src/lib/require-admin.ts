import "server-only";

import type { User } from "@supabase/supabase-js";
import { STAFF_RPC } from "@prisma-eco/contracts";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type AdminContext = {
  user: User;
  userId: string | null;
  adminId: string | null;
  role: string | null;
  permissions: Set<string>;
};

type StaffAuthPayload = {
  user_id?: string | null;
  admin_id?: string | null;
  role?: string | null;
  role_id?: string | null;
  telegram_id?: number | null;
  minecraft_nickname?: string | null;
  permissions?: unknown;
};

async function getAdminContext(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  user: User,
): Promise<AdminContext | null> {
  const { data, error } = await supabase.rpc(STAFF_RPC.authContext);
  if (error || !data || typeof data !== "object") return null;

  const payload = data as StaffAuthPayload;
  const permissions = new Set<string>(
    Array.isArray(payload.permissions)
      ? payload.permissions.filter((permission): permission is string => typeof permission === "string")
      : [],
  );

  if (!payload.user_id || !payload.admin_id || !payload.role) return null;

  return {
    user,
    userId: payload.user_id,
    adminId: payload.admin_id,
    role: payload.role,
    permissions,
  };
}

async function authenticatedAdminContext(options: { skipAalCheck?: boolean } = {}): Promise<AdminContext | null> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) return null;

  const context = await getAdminContext(supabase, user);
  if (!context) return null;

  if (!options.skipAalCheck) {
    const { data: aal, error: aalError } =
      await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

    if (aalError) return null;
    if (aal.nextLevel === "aal2" && aal.currentLevel !== "aal2") return null;
  }

  return context;
}

export async function requireAdmin(permission?: string): Promise<User | null> {
  const context = await authenticatedAdminContext();
  if (!context) return null;

  if (permission && !context.permissions.has("*") && !context.permissions.has(permission)) {
    return null;
  }

  return context.user;
}

export async function requireAdminContext(permission?: string): Promise<AdminContext | null> {
  const context = await authenticatedAdminContext();
  if (!context) return null;

  if (permission && !context.permissions.has("*") && !context.permissions.has(permission)) {
    return null;
  }

  return context;
}


/**
 * Used only by the MFA challenge/verification endpoint.
 * This still verifies the Supabase session and staff identity, but does not
 * require AAL2 before the user can submit the factor that upgrades it to AAL2.
 */
export async function requireAdminContextForMfa(): Promise<AdminContext | null> {
  return authenticatedAdminContext({ skipAalCheck: true });
}
