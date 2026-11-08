import { PARTICIPANT_CURRENT_USER_RPC, type ParticipantCurrentUser } from "@prisma-eco/contracts";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function getAuthUser() {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data?.claims?.sub) return null;
  return { id: String(data.claims.sub) };
}

export async function getCurrentUser() {
  const auth = await getAuthUser();
  if (!auth) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(PARTICIPANT_CURRENT_USER_RPC.get);
  if (error || !data || typeof data !== "object") return null;
  return { authId: auth.id, ...(data as ParticipantCurrentUser) };
}

export async function requireUser() {
  const user = await getCurrentUser();
  if (!user) redirect("/login");
  return user;
}
