/** OpenAI-compatible chat call (AnyModel by default). Keys come from env only. */
const BASE = (process.env.AI_BASE_URL || "https://anymodel.org/v1").replace(/\/$/, "");
const MODELS = [
  process.env.AI_MODEL_SITE || process.env.AI_MODEL_USER || "am/gpt-oss-20b",
  process.env.AI_MODEL_FALLBACK || "am/nemotron-3.5-lightning-30b-a3b",
];

export function aiConfigured(): boolean {
  return Boolean(process.env.AI_API_KEY_SITE || process.env.AI_API_KEY_USER);
}

export async function askModel(system: string, question: string): Promise<string> {
  const key = process.env.AI_API_KEY_SITE || process.env.AI_API_KEY_USER;
  if (!key) throw new Error("not configured");
  let lastError = "failed";
  for (const model of MODELS) {
    try {
      const response = await fetch(`${BASE}/chat/completions`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
        body: JSON.stringify({
          model,
          messages: [{ role: "system", content: system }, { role: "user", content: question }],
          max_tokens: 400,
          temperature: 0.2,
          stream: false,
        }),
        signal: AbortSignal.timeout(25_000),
      });
      if (!response.ok) {
        lastError = `HTTP ${response.status}`;
        continue;
      }
      const data = await response.json();
      const text = String(data?.choices?.[0]?.message?.content ?? "").trim();
      if (text) return text;
      lastError = "empty";
    } catch (error) {
      lastError = error instanceof Error ? error.name : "error";
    }
  }
  throw new Error(lastError);
}
