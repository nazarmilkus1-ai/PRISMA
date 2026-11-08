import "server-only";
import { createSupabaseAdminClient } from "./supabase/admin";

/** Checks an email against the allow-list: ADMIN_EMAILS env var (comma
 * separated) plus the admin_emails table (for allow-listing without a
 * redeploy). Either source is sufficient. */
export async function isAllowedAdminEmail(email: string): Promise<boolean> {
  const normalized = email.trim().toLowerCase();
  if (!normalized) return false;

  const fromEnv = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  if (fromEnv.includes(normalized)) return true;

  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return false;
  }

  const supabase = createSupabaseAdminClient();
  const { data, error } = await supabase
    .from("admin_emails")
    .select("email")
    .eq("email", normalized)
    .maybeSingle();

  if (error) {
    console.error("[admin-emails] lookup failed", error);
    return false;
  }
  return !!data;
}
