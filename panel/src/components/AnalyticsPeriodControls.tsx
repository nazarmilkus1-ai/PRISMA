const PERIODS = [
  ["24h", "День"],
  ["7d", "Неделя"],
  ["30d", "Месяц"],
  ["all", "Всё время"],
] as const;

export function AnalyticsPeriodControls({
  period,
  detailed,
}: {
  period: "24h" | "7d" | "30d" | "all";
  detailed: boolean;
}) {
  return (
    <div className="flex flex-wrap items-center gap-1 rounded-xl border border-border bg-panel p-1">
      {PERIODS.map(([value, label]) => (
        <a
          key={value}
          href={`?period=${value}${detailed ? "&detail=1" : ""}`}
          className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${period === value ? "bg-panel-raised text-moon" : "text-moon-dim hover:text-moon"}`}
        >
          {label}
        </a>
      ))}
      <a
        href={`?period=${period}${detailed ? "" : "&detail=1"}`}
        className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${detailed ? "bg-ember/15 text-ember" : "text-moon-dim hover:text-moon"}`}
      >
        {detailed ? "Сводка" : "Детально"}
      </a>
    </div>
  );
}
