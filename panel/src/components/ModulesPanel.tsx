"use client";

import { useMemo, useState } from "react";
import { MODULE_METADATA } from "@prisma-eco/contracts";
import type { ModuleId } from "@prisma-eco/contracts";

type ModuleRow = {
  id: ModuleId;
  title: string;
  protected: boolean;
  enabled: boolean;
  reason: string | null;
  updated_at: string;
};

function isEffectivelyEnabled(
  moduleId: ModuleId,
  modules: ModuleRow[],
  visited: Set<ModuleId> = new Set(),
): boolean {
  if (visited.has(moduleId)) return false;
  const module = modules.find((item) => item.id === moduleId);
  if (!module || !module.enabled) return false;
  const nextVisited = new Set(visited);
  nextVisited.add(moduleId);
  return MODULE_METADATA[moduleId].dependsOn.every((dependency) =>
    isEffectivelyEnabled(dependency, modules, nextVisited),
  );
}

export function ModulesPanel({
  modules: initialModules,
  canManage,
}: {
  modules: ModuleRow[];
  canManage: boolean;
}) {
  const [modules, setModules] = useState(initialModules);
  const [saving, setSaving] = useState<ModuleId | null>(null);
  const [reasonFor, setReasonFor] = useState<ModuleId | null>(null);
  const [reason, setReason] = useState("");
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return modules;
    return modules.filter((module) =>
      module.id.toLowerCase().includes(q) || module.title.toLowerCase().includes(q),
    );
  }, [modules, query]);

  const groups = useMemo(() => [
    {
      id: "minecraft",
      title: "Игровые механики Minecraft",
      description: "Отключение касается указанной функции. Родительские модули PRISMA могут дополнительно ограничивать её работу.",
      modules: filtered.filter((module) => module.id.startsWith("minecraft-")),
    },
    {
      id: "platform",
      title: "Остальные модули PRISMA",
      description: "Общие функции сайта, панели и сообщества.",
      modules: filtered.filter((module) => !module.id.startsWith("minecraft-")),
    },
  ].filter((group) => group.modules.length > 0), [filtered]);

  async function updateState(module: ModuleRow, enabled: boolean) {
    if (!canManage || module.protected) return;
    if (!enabled && !(reasonFor === module.id && reason.trim())) {
      window.alert("Укажите причину отключения механики.");
      return;
    }
    setSaving(module.id);
    try {
      const response = await fetch("/admin/api/modules", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          module_id: module.id,
          enabled,
          reason: (reasonFor === module.id ? reason : module.reason) || null,
        }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || "Не удалось изменить модуль.");
      setModules((current) =>
        current.map((item) =>
          item.id === module.id
            ? { ...item, enabled, reason: payload.reason ?? item.reason, updated_at: new Date().toISOString() }
            : item,
        ),
      );
      setReasonFor(null);
      setReason("");
    } catch (error) {
      window.alert(error instanceof Error ? error.message : "Не удалось изменить модуль.");
    } finally {
      setSaving(null);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="text-sm text-muted-foreground">
          {modules.filter((module) => isEffectivelyEnabled(module.id, modules)).length} из {modules.length} модулей активно с учётом зависимостей
        </div>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Поиск модуля…"
          className="h-9 w-full rounded-md border bg-background px-3 text-sm outline-none placeholder:text-muted-foreground focus:ring-2 focus:ring-ring/30 sm:max-w-xs"
        />
      </div>

      <div className="space-y-6">
        {groups.map((group) => (
          <section key={group.id} className="space-y-3">
            <div>
              <h2 className="text-base font-semibold">{group.title}</h2>
              <p className="mt-1 text-xs text-muted-foreground">{group.description}</p>
            </div>
            <div className="grid gap-3">
              {group.modules.map((module) => (
          <div key={module.id} className="rounded-xl border bg-card p-4">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="font-medium">{module.title}</h2>
                  <span className="rounded-full border px-2 py-0.5 font-mono text-[10px] text-muted-foreground">
                    {module.id}
                  </span>
                  {module.protected && (
                    <span className="rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-0.5 text-[10px] text-amber-600 dark:text-amber-300">
                      Защищён
                    </span>
                  )}
                </div>
                {module.reason && (
                  <p className="mt-2 text-xs text-muted-foreground">Причина: {module.reason}</p>
                )}
                {module.id === "minecraft-village-protection" && (
                  <p className="mt-2 text-xs text-amber-600 dark:text-amber-300">
                    Отключение снимет защиту территорий: игроки смогут строить и ломать блоки в сёлах.
                  </p>
                )}
              </div>

              <div className="flex items-center gap-3">
                {reasonFor === module.id && !module.protected && canManage ? (
                  <input
                    value={reason}
                    onChange={(event) => setReason(event.target.value.slice(0, 500))}
                    placeholder="Причина отключения"
                    className="h-9 w-56 rounded-md border bg-background px-3 text-xs outline-none focus:ring-2 focus:ring-ring/30"
                  />
                ) : null}

                <span className={"text-xs font-medium " + (isEffectivelyEnabled(module.id, modules) ? "text-emerald-600 dark:text-emerald-300" : "text-amber-600 dark:text-amber-300")}>
                  {!module.enabled ? "Отключён" : isEffectivelyEnabled(module.id, modules) ? "Активен" : "Зависимость отключена"}
                </span>

                <button
                  type="button"
                  disabled={!canManage || module.protected || saving === module.id}
                  onClick={() => {
                    if (module.enabled) {
                      setReasonFor(module.id);
                      setReason("");
                    } else {
                      void updateState(module, true);
                    }
                  }}
                  className="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full border transition-colors disabled:cursor-not-allowed disabled:opacity-40"
                  aria-label={module.enabled ? "Отключить модуль" : "Включить модуль"}
                  aria-pressed={module.enabled}
                >
                  <span
                    className={"size-4 rounded-full shadow-sm transition-transform " + (module.enabled ? "translate-x-6 bg-primary" : "translate-x-1 bg-muted-foreground")}
                  />
                </button>

                {reasonFor === module.id && !module.protected && canManage ? (
                  <button
                    type="button"
                    disabled={saving === module.id}
                    onClick={() => void updateState(module, false)}
                    className="h-9 rounded-md bg-primary px-3 text-xs font-medium text-primary-foreground disabled:opacity-50"
                  >
                    Отключить
                  </button>
                ) : null}
              </div>
            </div>
          </div>
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}
