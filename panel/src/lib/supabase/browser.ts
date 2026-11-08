"use client";
import { createBrowserClient } from "@supabase/ssr";

export function createSupabaseBrowserClient() {
  const publicKey =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !publicKey) {
    throw new Error("Missing Supabase public environment variables.");
  }

  return createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL, publicKey);
}
