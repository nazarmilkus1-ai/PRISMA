import {
  MODULE_IDS,
  MODULE_STATE_RPC,
  isModuleEffectivelyEnabled,
  type ModuleEnabledMap,
  type ModuleId,
} from "@prisma-eco/contracts";
import { createSupabasePublicClient } from "@/lib/supabase/public";

export async function getPublicModuleStates(): Promise<ModuleEnabledMap> {
  const db = createSupabasePublicClient();
  const { data, error } = await db.rpc(MODULE_STATE_RPC.list);

  if (error || !Array.isArray(data)) return {};

  const allowed = new Set<string>(MODULE_IDS);
  const states: ModuleEnabledMap = {};

  for (const row of data) {
    if (!row || typeof row !== "object") continue;
    const value = row as { module_id?: unknown; enabled?: unknown };
    if (
      typeof value.module_id === "string" &&
      allowed.has(value.module_id) &&
      typeof value.enabled === "boolean"
    ) {
      states[value.module_id as ModuleId] = value.enabled;
    }
  }

  return states;
}

export async function isPublicModuleEnabled(id: ModuleId): Promise<boolean> {
  return isModuleEffectivelyEnabled(id, await getPublicModuleStates());
}

export async function getPublicModuleAvailability(): Promise<ModuleEnabledMap> {
  const states = await getPublicModuleStates();
  return Object.fromEntries(
    MODULE_IDS.map((id) => [id, isModuleEffectivelyEnabled(id, states)]),
  ) as ModuleEnabledMap;
}
