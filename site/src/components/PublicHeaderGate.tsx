"use client";

import { usePathname } from "next/navigation";

export function PublicHeaderGate({ children }: { children: React.ReactNode }) {
  const pathname = usePathname() || "/";
  if (pathname === "/app" || pathname.startsWith("/app/")) {
    return null;
  }

  return <>{children}</>;
}
