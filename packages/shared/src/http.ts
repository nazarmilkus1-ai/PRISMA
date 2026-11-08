export async function fetchJson<T = Record<string, unknown>>(
  input: RequestInfo | URL,
  init?: RequestInit,
  fallback: T = {} as T,
): Promise<{ response: Response; data: T }> {
  const response = await fetch(input, init);
  const data = await response.json().catch(() => fallback);
  return { response, data };
}
