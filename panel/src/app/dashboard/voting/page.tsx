import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/require-admin";
import { VotingPanel } from "@/components/VotingPanel";
import { Card } from "@/components/ui";
import { STAFF_RPC } from "@prisma-eco/contracts";

type PollOptionRow = { position: number | null; text: string; votes: number | null };
type PollRow = { id: string; question: string; options: PollOptionRow[] | null; is_active: boolean | null; status: string; expires_at: string | null; closes_at: string | null; created_at: string };
type VotingPayload = { polls?: PollRow[]; server_rating?: { average?: number; total?: number } | null };

export default async function VotingPage() {
  const admin = await requireAdmin("poll.manage");
  if (!admin) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error: pollsError } = await supabase.rpc(STAFF_RPC.polls, { p_limit: 200 });
  const payload = (data ?? {}) as VotingPayload;
  const polls = payload.polls ?? [];

  const pollsWithVotes = polls.map((poll) => {
    const options = Array.isArray(poll.options) ? [...poll.options].sort((a, b) => Number(a.position ?? 0) - Number(b.position ?? 0)) : [];
    return {
      id: poll.id,
      question: poll.question,
      options: options.map((option) => option.text),
      is_active: !!poll.is_active && poll.status === "active" && (!poll.expires_at || new Date(poll.expires_at).getTime() > Date.now()),
      closes_at: poll.closes_at ?? poll.expires_at,
      created_at: poll.created_at,
      votes: options.map((option) => Number(option.votes ?? 0)),
    };
  });

  const serverRating = payload.server_rating
    ? { average: Number(payload.server_rating.average ?? 0), total: Number(payload.server_rating.total ?? 0) }
    : null;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-2xl text-moon">Голосування</h1>
          <p className="mt-1 text-sm text-moon-dim">Один источник данных для панели и Telegram-бота</p>
        </div>
        {serverRating && (
          <Card className="px-5 py-3 text-right">
            <p className="text-xs uppercase tracking-wide text-moon-dim">Оценка сервера</p>
            <p className="font-display text-2xl text-moon">{serverRating.average.toFixed(1)} <span className="text-sm text-moon-dim">/ 5</span></p>
            <p className="text-xs text-moon-dim">{serverRating.total} оценок</p>
          </Card>
        )}
      </div>
      {pollsError && <div className="rounded-xl border border-danger/30 bg-danger/10 p-4 text-sm text-danger">Не удалось загрузить голосования: {pollsError.message}</div>}
      <VotingPanel initialPolls={pollsWithVotes} />
    </div>
  );
}
