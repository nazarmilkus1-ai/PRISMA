import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth";

export async function requireMember() {
  const user = await requireUser();
  if (user.is_banned || user.status !== "ACCEPTED") redirect("/?memberOnly=1");
  return user;
}
