import { NextResponse } from "next/server";
import { aiConfigured, askModel } from "@/lib/ai/gateway";
import { SYSTEM_PROMPT, fastAnswer } from "@/lib/ai/knowledge";

export const dynamic = "force-dynamic";

const WINDOW_MS = 60_000;
const PER_MINUTE = 6;
const hits = new Map<string, number[]>();
// Hard ceiling on model calls per server instance and hour, so a distributed burst cannot run up the bill.
const MODEL_CALLS_PER_HOUR = 300;
let modelWindowStart = Date.now();
let modelCalls = 0;

function modelBudgetLeft(): boolean {
  const now = Date.now();
  if (now - modelWindowStart > 3_600_000) {
    modelWindowStart = now;
    modelCalls = 0;
  }
  return ++modelCalls <= MODEL_CALLS_PER_HOUR;
}

/** Best-effort per-instance limiter (no shared store by design); the gateway enforces the real quota. */
function limited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  if (recent.length >= PER_MINUTE) {
    hits.set(ip, recent);
    return true;
  }
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return false;
}

export async function POST(request: Request) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  if (limited(ip)) return NextResponse.json({ answer: "Слишком много вопросов подряд. Попробуйте через минуту.", links: [] }, { status: 429 });

  let question = "";
  try {
    const body = await request.json();
    question = String(body?.question ?? "").trim().slice(0, 500);
  } catch {
    return NextResponse.json({ error: "bad request" }, { status: 400 });
  }
  if (question.length < 2) return NextResponse.json({ error: "empty" }, { status: 400 });

  const fast = fastAnswer(question);
  if (fast) return NextResponse.json(fast);

  if (!aiConfigured()) {
    return NextResponse.json({
      answer: "Умный помощник пока не подключён. Загляните в Wiki или напишите в поддержку через бота.",
      links: [{ href: "/wiki", label: "Wiki" }, { href: "/rules", label: "Правила" }],
    });
  }
  if (!modelBudgetLeft()) {
    return NextResponse.json({
      answer: "Помощник сейчас перегружен. Загляните в Wiki или попробуйте позже.",
      links: [{ href: "/wiki", label: "Wiki" }],
    });
  }
  try {
    const answer = await askModel(SYSTEM_PROMPT, question);
    return NextResponse.json({ answer, links: [] });
  } catch {
    return NextResponse.json({
      answer: "Умный помощник сейчас недоступен, но вот куда можно заглянуть: в Wiki — инструкции и правила, заявку можно подать за минуту.",
      links: [{ href: "/wiki", label: "Wiki" }, { href: "/rules", label: "Правила" }, { href: "/apply", label: "Подать заявку" }],
    });
  }
}
