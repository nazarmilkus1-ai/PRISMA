import { notFound } from "next/navigation";
import type { ModuleId } from "@prisma-eco/contracts";
import { isPublicModuleEnabled } from "@/lib/modules";
import { requireMember } from "@/lib/member";
import { requireUser } from "@/lib/auth";

export async function requireModule(id: ModuleId) {
  if (!(await isPublicModuleEnabled(id))) notFound();
}

export async function requireModuleUser(id: ModuleId) {
  await requireModule(id);
  return requireUser();
}

export async function requireModuleMember(id: ModuleId) {
  await requireModule(id);
  return requireMember();
}
