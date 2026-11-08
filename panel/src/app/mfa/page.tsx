import { MfaChallenge } from "@/components/MfaChallenge";

export const dynamic = "force-dynamic";

function safeNext(value: string | undefined) {
  if (!value || !value.startsWith("/dashboard") || value.startsWith("//")) return "/dashboard";
  return value;
}

export default async function MfaPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const params = await searchParams;
  return <MfaChallenge nextPath={safeNext(params.next)} initialError={params.error ?? null} />;
}
