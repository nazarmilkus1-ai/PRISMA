import { MODULE_METADATA, type ModuleId } from "./modules.generated";

export type ModuleEnabledMap = Partial<Record<ModuleId, boolean>>;

export function isModuleEffectivelyEnabled(
  id: ModuleId,
  states: ModuleEnabledMap,
): boolean {
  const visiting = new Set<ModuleId>();

  function visit(current: ModuleId): boolean {
    if (states[current] !== true) return false;
    if (visiting.has(current)) return false;

    visiting.add(current);
    const enabled = MODULE_METADATA[current].dependsOn.every(visit);
    visiting.delete(current);
    return enabled;
  }

  return visit(id);
}
