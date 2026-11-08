"use client";
import type { ReactNode } from "react";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

const tooltipStyle = {
  background: "var(--color-panel-raised)",
  border: "1px solid var(--color-border)",
  borderRadius: 8,
  fontSize: 12,
  color: "var(--color-moon)",
};
const axisStyle = { fontSize: 11, fill: "var(--color-moon-dim)" };


function chartWidth(count: number) {
  if (count <= 24) return 760;
  if (count <= 48) return count * 36;
  if (count <= 180) return count * 32;
  return count * 28;
}

function axisInterval(count: number) {
  if (count <= 24) return 0;
  if (count <= 48) return 1;
  if (count <= 120) return 5;
  if (count <= 240) return 11;
  if (count <= 720) return 23;
  return 47;
}

function ChartViewport({
  count,
  height,
  children,
}: {
  count: number;
  height: number;
  children: React.ReactNode;
}) {
  const minWidth = chartWidth(count);
  return (
    <div className="overflow-x-auto pb-1">
      <div style={{ minWidth: minWidth + "px" }}>
        <ResponsiveContainer width="100%" height={height}>
          {children}
        </ResponsiveContainer>
      </div>
      {count > 28 ? (
        <p className="mt-1 px-1 text-[10px] text-moon-dim">
          Листайте график вправо и влево
        </p>
      ) : null}
    </div>
  );
}

export function UserGrowthChart({ data }: { data: { date: string; count: number }[] }) {
  return (
    <ChartViewport count={data.length} height={220}>
      <AreaChart data={data}>
        <defs>
          <linearGradient id="growthFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="var(--color-ember)" stopOpacity={0.35} />
            <stop offset="95%" stopColor="var(--color-ember)" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" vertical={false} />
        <XAxis dataKey="date" tick={axisStyle} axisLine={false} tickLine={false} interval={axisInterval(data.length)} />
        <YAxis tick={axisStyle} axisLine={false} tickLine={false} width={32} allowDecimals={false} />
        <Tooltip contentStyle={tooltipStyle} />
        <Area type="monotone" dataKey="count" stroke="var(--color-ember)" fill="url(#growthFill)" strokeWidth={2} />
      </AreaChart>
    </ChartViewport>
  );
}

export function AcceptanceRateChart({ data }: { data: Record<string, number> }) {
  const chartData = [
    { name: "Принято", value: data.ACCEPTED ?? 0, color: "var(--color-success)" },
    { name: "На рассмотрении", value: data.PENDING ?? 0, color: "var(--color-warn)" },
    { name: "Отклонено", value: data.REJECTED ?? 0, color: "var(--color-danger)" },
  ];
  const total = chartData.reduce((sum, d) => sum + d.value, 0);

  return (
    <ResponsiveContainer width="100%" height={220}>
      <PieChart>
        <Pie data={chartData} dataKey="value" nameKey="name" innerRadius={55} outerRadius={80} paddingAngle={2}>
          {chartData.map((d) => (
            <Cell key={d.name} fill={d.color} stroke="var(--color-panel)" strokeWidth={2} />
          ))}
        </Pie>
        <Tooltip contentStyle={tooltipStyle} formatter={(value) => { const n = Number(value ?? 0); return [n + " (" + (total ? Math.round((n / total) * 100) : 0) + "%)", ""]; }} />
      </PieChart>
    </ResponsiveContainer>
  );
}

export function ServerRatingChart({ data }: { data: { star: string; count: number }[] }) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" vertical={false} />
        <XAxis dataKey="star" tick={axisStyle} axisLine={false} tickLine={false} />
        <YAxis tick={axisStyle} axisLine={false} tickLine={false} width={24} allowDecimals={false} />
        <Tooltip contentStyle={tooltipStyle} />
        <Bar dataKey="count" fill="var(--color-curse)" radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function ActivePlayersChart({ data }: { data: { date: string; count: number }[] }) {
  return (
    <ChartViewport count={data.length} height={220}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" vertical={false} />
        <XAxis dataKey="date" tick={axisStyle} axisLine={false} tickLine={false} interval={axisInterval(data.length)} />
        <YAxis tick={axisStyle} axisLine={false} tickLine={false} width={32} allowDecimals={false} />
        <Tooltip contentStyle={tooltipStyle} />
        <Line type="monotone" dataKey="count" stroke="var(--color-curse)" strokeWidth={2} dot={false} />
      </LineChart>
    </ChartViewport>
  );
}

export function ChatActivityComboChart({ data }: { data: { date: string; messages: number; unique_players: number }[] }) {
  return (
    <ChartViewport count={data.length} height={240}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" vertical={false} />
        <XAxis dataKey="date" tick={axisStyle} axisLine={false} tickLine={false} interval={axisInterval(data.length)} />
        <YAxis yAxisId="left" tick={axisStyle} axisLine={false} tickLine={false} width={36} allowDecimals={false} />
        <YAxis yAxisId="right" orientation="right" tick={axisStyle} axisLine={false} tickLine={false} width={36} allowDecimals={false} />
        <Tooltip contentStyle={tooltipStyle} />
        <Line yAxisId="left" type="monotone" dataKey="messages" name="Сообщения" stroke="var(--color-ember)" strokeWidth={2} dot={false} />
        <Line yAxisId="right" type="monotone" dataKey="unique_players" name="Уникальные игроки" stroke="var(--color-curse)" strokeWidth={2} dot={false} />
      </LineChart>
    </ChartViewport>
  );
}

export function AdminActivityChart({ data }: { data: { date: string; total_actions: number; active_admins: number }[] }) {
  return (
    <ChartViewport count={data.length} height={240}>
      <BarChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" vertical={false} />
        <XAxis dataKey="date" tick={axisStyle} axisLine={false} tickLine={false} interval={axisInterval(data.length)} />
        <YAxis tick={axisStyle} axisLine={false} tickLine={false} width={36} allowDecimals={false} />
        <Tooltip contentStyle={tooltipStyle} />
        <Bar dataKey="total_actions" name="Действия" fill="var(--color-ember)" radius={[4, 4, 0, 0]} />
        <Bar dataKey="active_admins" name="Активные админы" fill="var(--color-curse)" radius={[4, 4, 0, 0]} />
      </BarChart>
    </ChartViewport>
  );
}
