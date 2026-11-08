import React from "react";
import {
  Alert,
  InfoItem,
  Card,
  Pagination,
  Tabs,
} from "@prisma-eco/ui";

export { Alert, InfoItem, Card, Pagination, Tabs };
export function Skeleton({
  className = "",
}: {
  className?: string;
}) {
  return <div aria-hidden="true" className={"prisma-skeleton rounded-md " + className} />;
}

const AVATAR_SIZES = {
  sm: "size-7 text-[10px]",
  md: "size-9 text-xs",
  lg: "size-11 text-sm",
} as const;

export function Avatar({
  name,
  size = "md",
}: {
  name: string;
  size?: keyof typeof AVATAR_SIZES;
}) {
  return (
    <span
      aria-hidden="true"
      className={"prisma-glass-surface inline-flex shrink-0 items-center justify-center rounded-full border font-medium text-muted-foreground " + AVATAR_SIZES[size]}
    >
      {initials(name)}
    </span>
  );
}

export function SearchBar({
  value,
  onChange,
  placeholder,
  className = "",
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
}) {
  return (
    <input
      type="search"
      value={value}
      onChange={(event) => onChange(event.target.value)}
      placeholder={placeholder}
      aria-label={placeholder ?? "Поиск"}
      className={"prisma-glass-control min-w-0 w-full rounded-lg border border-border bg-panel-raised px-3 py-2 text-sm text-moon outline-none focus:border-curse " + className}
    />
  );
}

export function StatCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: string | number;
  hint?: string;
}) {
  return (
    <Card className="p-5">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tracking-tight">{value}</p>
      {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
    </Card>
  );
}

export type BadgeTone = "success" | "danger" | "warn" | "curse" | "neutral";

const TONE_STYLES: Record<BadgeTone, string> = {
  success: "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900/60 dark:bg-emerald-950/30 dark:text-emerald-300",
  danger: "border-red-200 bg-red-50 text-red-700 dark:border-red-900/60 dark:bg-red-950/30 dark:text-red-300",
  warn: "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-900/60 dark:bg-amber-950/30 dark:text-amber-300",
  curse: "border-border bg-muted text-foreground",
  neutral: "border-border bg-muted text-muted-foreground",
};

export function Badge({
  tone = "neutral",
  children,
}: {
  tone?: BadgeTone;
  children: React.ReactNode;
}) {
  return (
    <span className={"prisma-glass-badge inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium " + TONE_STYLES[tone]}>
      {children}
    </span>
  );
}

const STATUS_TONE: Record<string, BadgeTone> = {
  PENDING: "warn",
  ACCEPTED: "success",
  REJECTED: "danger",
};

const STATUS_LABELS: Record<string, string> = {
  PENDING: "На рассмотрении",
  ACCEPTED: "Принята",
  REJECTED: "Отклонена",
};

export function StatusBadge({ status }: { status: string }) {
  return (
    <Badge tone={STATUS_TONE[status] ?? "neutral"}>
      {STATUS_LABELS[status] ?? status}
    </Badge>
  );
}

const MOD_TONE: Record<string, BadgeTone> = {
  WARN: "warn",
  MUTE: "curse",
  KICK: "danger",
  BAN: "danger",
  UNMUTE: "success",
};

const MOD_LABELS: Record<string, string> = {
  WARN: "Варн",
  MUTE: "Мут",
  KICK: "Кик",
  BAN: "Бан",
  UNMUTE: "Размут",
};

export function ModerationBadge({ type }: { type: string }) {
  return <Badge tone={MOD_TONE[type] ?? "neutral"}>{MOD_LABELS[type] ?? type}</Badge>;
}

function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("") || "?";
}

export type AlertTone = "success" | "danger" | "warn" | "info";

const ALERT_STYLES: Record<AlertTone, string> = {
  success: "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900/60 dark:bg-emerald-950/30 dark:text-emerald-300",
  danger: "border-red-200 bg-red-50 text-red-700 dark:border-red-900/60 dark:bg-red-950/30 dark:text-red-300",
  warn: "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-900/60 dark:bg-amber-950/30 dark:text-amber-300",
  info: "border-border bg-muted text-foreground",
};

const ALERT_ICON: Record<AlertTone, string> = {
  success: "✓",
  danger: "!",
  warn: "!",
  info: "i",
};

const PROGRESS_FILL: Record<string, string> = {
  ember: "bg-primary",
  curse: "bg-primary",
  success: "bg-emerald-500",
  warn: "bg-amber-500",
  danger: "bg-red-500",
};

export function ProgressBar({
  value,
  max = 100,
  tone = "ember",
  label,
}: {
  value: number;
  max?: number;
  tone?: "ember" | "curse" | "success" | "warn" | "danger";
  label?: string;
}) {
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  return (
    <div>
      {label && (
        <div className="mb-1 flex justify-between text-xs text-muted-foreground">
          <span>{label}</span>
          <span>{Math.round(pct)}%</span>
        </div>
      )}
      <div className="prisma-glass-surface h-2 w-full overflow-hidden rounded-full border">
        <div className={"h-full rounded-full transition-all " + PROGRESS_FILL[tone]} style={{ width: pct + "%" }} />
      </div>
    </div>
  );
}

export function ToggleSwitch({
  checked,
  onChange,
  label,
  disabled,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label?: string;
  disabled?: boolean;
}) {
  return (
    <label className={"flex items-center justify-between gap-3 " + (disabled ? "opacity-50" : "cursor-pointer")}>
      {label && <span className="text-sm">{label}</span>}
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={"relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors " + (checked ? "bg-primary" : "prisma-glass-control border")}
      >
        <span className={"inline-block size-4 rounded-full bg-card shadow-sm transition-transform " + (checked ? "translate-x-6" : "translate-x-1")} />
      </button>
    </label>
  );
}

