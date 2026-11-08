export type FormatDateInput = string | number | Date;

export function formatDateTime(value: FormatDateInput): string {
  return new Date(value).toLocaleString("ru-RU");
}

export function formatDate(value: FormatDateInput): string {
  return new Date(value).toLocaleDateString("ru-RU");
}

export function formatNumber(value: number): string {
  return Number(value).toLocaleString("ru-RU");
}

export function formatMinutes(totalMinutes: number): string {
  const value = Math.max(0, Number(totalMinutes) || 0);
  const days = Math.floor(value / 1440);
  const hours = Math.floor((value % 1440) / 60);
  const minutes = value % 60;

  if (days) return days + " д " + hours + " ч";
  if (hours) return hours + " ч " + minutes + " мин";
  return minutes + " мин";
}

export function formatBytes(value: number | null | undefined): string {
  const bytes = Math.max(0, Number(value) || 0);
  if (!bytes) return "0 B";

  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const amount = bytes / 1024 ** index;

  return amount >= 100 || index === 0
    ? Math.round(amount) + " " + units[index]
    : amount.toFixed(1) + " " + units[index];
}

export function formatMegabytes(value: number | null | undefined): string {
  if (value == null) return "—";
  if (value >= 1024) return `${(value / 1024).toFixed(1)} GB`;
  return `${value} MB`;
}

export function formatUptimeUk(totalSeconds: number | null | undefined): string {
  if (totalSeconds == null) return "—";
  const seconds = Math.max(0, Math.floor(Number(totalSeconds) || 0));
  const d = Math.floor(seconds / 86400), h = Math.floor((seconds % 86400) / 3600), m = Math.floor((seconds % 3600) / 60);
  return d ? `${d}д ${h}г` : h ? `${h}г ${m}хв` : `${m}хв`;
}

export function formatUptime(totalSeconds: number | null | undefined): string {
  const seconds = Math.max(0, Math.floor(Number(totalSeconds) || 0));
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  if (days) return days + " д " + hours + " ч";
  if (hours) return hours + " ч " + minutes + " мин";
  return minutes + " мин";
}
