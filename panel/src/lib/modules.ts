import "server-only";

import {
  MODULE_IDS,
  STAFF_MODULE_RPC,
  type ModuleId,
  type StaffModuleState,
} from "@prisma-eco/contracts";
import { createSupabaseServerClient } from "@/lib/supabase/server";

function normalizeStates(data: unknown): StaffModuleState[] {
  if (!Array.isArray(data)) return [];
  const allowed = new Set<string>(MODULE_IDS);

  return data.flatMap((row) => {
    if (!row || typeof row !== "object") return [];
    const value = row as Partial<StaffModuleState>;
    if (
      typeof value.module_id !== "string" ||
      !allowed.has(value.module_id) ||
      typeof value.enabled !== "boolean"
    ) {
      return [];
    }

    return [{
      module_id: value.module_id as ModuleId,
      enabled: value.enabled,
      reason: typeof value.reason === "string" ? value.reason : null,
      updated_by: typeof value.updated_by === "string" ? value.updated_by : null,
      updated_at: typeof value.updated_at === "string"
        ? value.updated_at
        : new Date(0).toISOString(),
    }];
  });
}

export async function getStaffModuleStates(): Promise<{
  states: StaffModuleState[];
  error: string | null;
}> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(STAFF_MODULE_RPC.list);

  return {
    states: normalizeStates(data),
    error: error ? "Не удалось загрузить состояние модулей." : null,
  };
}

export async function setStaffModuleState(input: {
  module_id: ModuleId;
  enabled: boolean;
  reason?: string | null;
}) {
  const supabase = await createSupabaseServerClient();

  return supabase.rpc(STAFF_MODULE_RPC.set, {
    p_module_id: input.module_id,
    p_enabled: input.enabled,
    p_reason: input.reason ?? null,
  });
}
