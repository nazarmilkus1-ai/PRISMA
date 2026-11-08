"use client";

import { formatDateTime } from "@prisma-eco/shared";

import { REPORT_STATUS_LABELS, REPORT_TYPE_LABELS } from "@prisma-eco/contracts";

import { useEffect, useMemo, useState } from "react";
import {
  Alert, Badge, Button, Card, CardContent, CardHeader, CardTitle, Dialog,
  DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, Input,
  SimplePagination, Skeleton, Table, TableBody, TableCell, TableHead, TableHeader, TableRow, Tabs,
  Textarea, InfoItem,
} from "@prisma-eco/ui";

type ReportStatus = "OPEN" | "IN_REVIEW" | "RESOLVED" | "DISMISSED";
type Report = {
  id: string;
  ticket_no: number | null;
  type: "BUG" | "SERVER" | "PLAYER";
  target_nickname: string | null;
  description: string;
  status: ReportStatus;
  created_at: string;
  updated_at: string;
  priority: string | null;
  category: string | null;
  evidence: unknown;
  involved_players: unknown;
  coordinates: unknown;
  internal_notes: string | null;
  assigned_to: string | null;
  resolved_at: string | null;
  users: any;
};
type Detail = Report & {
  history: Array<{
    id: number;
    from_status: string | null;
    to_status: string | null;
    note: string | null;
    created_at: string;
  }>;
};

const FILTERS = [
  { key: "OPEN", label: "Открытые" },
  { key: "IN_REVIEW", label: "В работе" },
  { key: "RESOLVED", label: "Решённые" },
  { key: "DISMISSED", label: "Отклонённые" },
  { key: "ALL", label: "Все" },
] as const;
const PAGE_SIZE = 15;

function statusVariant(status: ReportStatus) {
  switch (status) {
    case "OPEN":
      return "secondary" as const;
    case "IN_REVIEW":
      return "warning" as const;
    case "RESOLVED":
      return "success" as const;
    default:
      return "destructive" as const;
  }
}

function reporter(report: Report) {
  const user = Array.isArray(report.users) ? report.users[0] : report.users;
  return user?.minecraft_nickname || user?.telegram_username || "Пользователь";
}

export function ReportsWorkspace() {
  const [rows, setRows] = useState<Report[] | null>(null);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["key"]>("OPEN");
  const [page, setPage] = useState(1);
  const [query, setQuery] = useState("");
  const [detail, setDetail] = useState<Detail | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notes, setNotes] = useState("");
  const [players, setPlayers] = useState("");

  async function load() {
    try {
      setError("");
      const response = await fetch("/admin/api/reports", { cache: "no-store" });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Не удалось загрузить репорты.");
      setRows(payload.reports || []);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Не удалось загрузить репорты.");
    }
  }

  useEffect(() => {
    void load();
  }, []);

  const filtered = useMemo(() => {
    if (!rows) return [];
    const q = query.trim().toLowerCase();
    return rows
      .filter((report) => filter === "ALL" || report.status === filter)
      .filter(
        (report) =>
          !q ||
          report.description.toLowerCase().includes(q) ||
          (report.target_nickname || "").toLowerCase().includes(q) ||
          (report.ticket_no ? String(report.ticket_no) : "").includes(q),
      );
  }, [rows, filter, query]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const current = Math.min(page, totalPages);
  const visible = filtered.slice((current - 1) * PAGE_SIZE, current * PAGE_SIZE);

  async function openReport(id: string) {
    setLoadingDetail(true);
    setError("");
    try {
      const response = await fetch("/admin/api/reports/" + id, { cache: "no-store" });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Не удалось загрузить репорт.");
      setDetail(payload);
      setNotes(payload.internal_notes || "");
      setPlayers(Array.isArray(payload.involved_players) ? payload.involved_players.join("\n") : "");
    } catch (error) {
      setError(error instanceof Error ? error.message : "Не удалось загрузить репорт.");
    } finally {
      setLoadingDetail(false);
    }
  }

  async function changeStatus(status: ReportStatus) {
    if (!detail) return;
    setBusy(true);
    setError("");

    try {
      const response = await fetch("/admin/api/reports/" + detail.id, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          status,
          internal_notes: notes || null,
          involved_players: players.split(/[\n,]+/).map((value) => value.trim()).filter(Boolean),
        }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Не удалось обновить репорт.");
      await load();
      await openReport(detail.id);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Не удалось обновить репорт.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      {error ? <Alert variant="destructive">{error}</Alert> : null}

      <Card className="overflow-hidden">
        <CardHeader>
          <CardTitle>Очередь репортов</CardTitle>
          <p className="text-sm text-muted-foreground">
            Открытые обращения находятся в начале очереди; после взятия в работу они закрепляются за модератором.
          </p>
        </CardHeader>

        <div className="px-4 pt-1">
          <Tabs
            tabs={FILTERS.map((tab) => ({
              ...tab,
              count: rows ? rows.filter((report) => tab.key === "ALL" || report.status === tab.key).length : undefined,
            }))}
            active={filter}
            onChange={(value) => {
              setFilter(value as typeof filter);
              setPage(1);
            }}
          />
        </div>

        <CardContent className="border-b">
          <div className="flex flex-col gap-2 sm:flex-row">
            <Input
              value={query}
              onChange={(event) => {
                setQuery(event.target.value);
                setPage(1);
              }}
              placeholder="Поиск по номеру, цели или описанию"
              aria-label="Поиск репортов"
            />
            <Button variant="outline" onClick={() => void load()}>Обновить</Button>
          </div>
        </CardContent>

        {rows === null ? (
          <div className="space-y-3 p-5">
            <Skeleton className="h-10" />
            <Skeleton className="h-10" />
            <Skeleton className="h-10" />
          </div>
        ) : visible.length === 0 ? (
          <div className="p-8 text-center text-sm text-muted-foreground">Репортов по текущему фильтру нет.</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>№</TableHead>
                <TableHead>Репорт</TableHead>
                <TableHead>Цель</TableHead>
                <TableHead>Приоритет</TableHead>
                <TableHead>Статус</TableHead>
                <TableHead>Создан</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {visible.map((report) => (
                <TableRow
                  key={report.id}
                  className="cursor-pointer focus-within:bg-muted/60"
                  onClick={() => void openReport(report.id)}
                  tabIndex={0}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" || event.key === " ") {
                      event.preventDefault();
                      void openReport(report.id);
                    }
                  }}
                  aria-label={"Открыть репорт " + (report.ticket_no ? "#" + report.ticket_no : report.id.slice(0, 8))}
                >
                  <TableCell className="font-mono text-xs text-muted-foreground">
                    {report.ticket_no ? "#" + report.ticket_no : report.id.slice(0, 8)}
                  </TableCell>
                  <TableCell>
                    <p className="max-w-xl truncate font-medium">{REPORT_TYPE_LABELS[report.type] ?? report.type} · {reporter(report)}</p>
                    <p className="mt-0.5 max-w-xl truncate text-xs text-muted-foreground">{report.description}</p>
                  </TableCell>
                  <TableCell>{report.target_nickname || "—"}</TableCell>
                  <TableCell>{report.priority || "NORMAL"}</TableCell>
                  <TableCell><Badge variant={statusVariant(report.status)}>{REPORT_STATUS_LABELS[report.status] ?? report.status}</Badge></TableCell>
                  <TableCell className="text-xs text-muted-foreground">{formatDateTime(report.created_at)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}

        {rows && totalPages > 1 ? (
          <div className="border-t p-4">
            <SimplePagination page={current} totalPages={totalPages} onChange={setPage} />
          </div>
        ) : null}
      </Card>

      <Dialog open={!!detail} onOpenChange={(open) => !open && setDetail(null)}>
        {detail ? (
          <DialogContent className="space-y-5">
            <DialogHeader>
              <div>
                <DialogTitle>
                  Репорт {detail.ticket_no ? "#" + detail.ticket_no : detail.id.slice(0, 8)}
                </DialogTitle>
                <DialogDescription>
                  {REPORT_TYPE_LABELS[detail.type] ?? detail.type} · {reporter(detail)} · {REPORT_STATUS_LABELS[detail.status] ?? detail.status}
                </DialogDescription>
              </div>
            </DialogHeader>

            {loadingDetail ? (
                <Skeleton className="h-32" />
              ) : (
                <>
                  <div className="grid gap-3 sm:grid-cols-3">
                    <InfoItem label="Статус"><Badge variant={statusVariant(detail.status)}>{REPORT_STATUS_LABELS[detail.status] ?? detail.status}</Badge></InfoItem>
                    <InfoItem label="Цель">{detail.target_nickname || "—"}</InfoItem>
                    <InfoItem label="Приоритет">{detail.priority || "NORMAL"}</InfoItem>
                  </div>

                  <div>
                    <p className="text-xs text-muted-foreground">Описание</p>
                    <p className="mt-1 whitespace-pre-wrap rounded-md border bg-muted/30 p-3 text-sm leading-6">{detail.description}</p>
                  </div>

                  <div>
                    <p className="text-xs text-muted-foreground">Участники</p>
                    <Input value={players} onChange={(event) => setPlayers(event.target.value)} placeholder="Ники через запятую или с новой строки" />
                  </div>

                  <div>
                    <p className="text-xs text-muted-foreground">Внутренние заметки</p>
                    <Textarea value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={5000} placeholder="Заметки модерации" />
                  </div>

                  <div>
                    <p className="text-xs text-muted-foreground">История</p>
                    <div className="mt-2 space-y-2">
                      {detail.history?.length ? detail.history.map((history) => (
                        <div key={history.id} className="rounded-md border bg-muted/20 p-2.5 text-xs">
                          <span className="font-medium">{history.from_status || "—"} → {history.to_status || "—"}</span>
                          <span className="ml-2 text-muted-foreground">{formatDateTime(history.created_at)}</span>
                          {history.note ? <p className="mt-1 whitespace-pre-wrap text-muted-foreground">{history.note}</p> : null}
                        </div>
                      )) : <p className="text-sm text-muted-foreground">История пуста.</p>}
                    </div>
                  </div>
                </>
            )}
            <DialogFooter>
              {detail.status === "OPEN" ? (
                <Button loading={busy} variant="secondary" onClick={() => void changeStatus("IN_REVIEW")}>
                  Взять в работу
                </Button>
              ) : null}
              {(detail.status === "OPEN" || detail.status === "IN_REVIEW") ? (
                <>
                  <Button loading={busy && false} onClick={() => void changeStatus("RESOLVED")}>Решить</Button>
                  <Button disabled={busy} variant="destructive" onClick={() => void changeStatus("DISMISSED")}>Отклонить</Button>
                </>
              ) : null}
            </DialogFooter>
          </DialogContent>
        ) : null}
      </Dialog>
    </div>
  );
}
