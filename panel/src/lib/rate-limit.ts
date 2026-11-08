import "server-only";
import { AUTH_RATE_LIMIT_RPC } from "@prisma-eco/contracts";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export async function consumeAuthRateLimit(bucket: string, limit = 10, windowSeconds = 600) {
  const { data, error } = await createSupabaseAdminClient().rpc(AUTH_RATE_LIMIT_RPC.consume, {
    p_bucket: bucket,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });

  if (error) {
    console.error("[panel/rate-limit] rpc failed", error);
    return false;
  }

  return data === true;
}
