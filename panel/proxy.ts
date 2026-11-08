import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Edge-runtime-safe allow-list check: a plain REST call instead of the
// @supabase/supabase-js admin client, so this has no Node-specific
// dependencies and stays cheap on every /dashboard request. Mirrors
// lib/admin-emails.ts's logic (env var OR admin_emails table) but doesn't
// import it directly, since that file is marked "server-only" for route
// handlers/Server Components, not proxy/middleware.
async function isAllowedAdminEmail(email: string): Promise<boolean> {
  const normalized = email.trim().toLowerCase();
  if (!normalized) return false;

  const fromEnv = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  if (fromEnv.includes(normalized)) return true;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return false;

  try {
    const res = await fetch(
      `${url}/rest/v1/admin_emails?select=email&email=eq.${encodeURIComponent(normalized)}`,
      { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
    );
    if (!res.ok) return false;
    const rows = (await res.json()) as unknown[];
    return rows.length > 0;
  } catch (err) {
    console.error("[proxy] admin_emails lookup failed", err);
    return false;
  }
}

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const publicKey =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !publicKey) {
    return NextResponse.redirect(new URL("/admin?error=auth_unavailable", request.url));
  }

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    publicKey,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options as Parameters<typeof response.cookies.set>[2])
          );
        },
      },
    },
  );

  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();
  const claims = claimsData?.claims;
  const userId = typeof claims?.sub === "string" ? claims.sub : null;
  const userEmail = typeof claims?.email === "string" ? claims.email : null;

  if (request.nextUrl.pathname.startsWith("/api/") && ["POST", "PUT", "PATCH", "DELETE"].includes(request.method)) {
    const origin = request.headers.get("origin");
    const expectedOrigin = new URL(request.url).origin;
    if (origin && origin !== expectedOrigin) {
      return NextResponse.json({ error: "csrf_rejected" }, { status: 403 });
    }
    const fetchSite = request.headers.get("sec-fetch-site");
    if (fetchSite && !["same-origin", "same-site", "none"].includes(fetchSite)) {
      return NextResponse.json({ error: "csrf_rejected" }, { status: 403 });
    }
  }

  if (!userId && (request.nextUrl.pathname.startsWith("/admin/dashboard") || request.nextUrl.pathname.startsWith("/dashboard"))) {
    return NextResponse.redirect(new URL("/admin", request.url));
  }

  // Defense in depth: even a valid Supabase session must belong to an
  // allow-listed email. This lets revoking access (removing a row from
  // admin_emails or an env var) take effect immediately, without needing
  // to invalidate that admin's existing session.
  if (userId && (request.nextUrl.pathname.startsWith("/admin/dashboard") || request.nextUrl.pathname.startsWith("/dashboard"))) {
    if (claimsError) return NextResponse.redirect(new URL("/?error=auth_unavailable", request.url));
    const allowed = userEmail ? await isAllowedAdminEmail(userEmail) : false;
    if (!allowed) {
      await supabase.auth.signOut();
      return NextResponse.redirect(new URL("/admin?error=not_an_admin", request.url));
    }
  }

  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

export const config = {
  matcher: ["/admin/:path*", "/dashboard/:path*", "/api/:path*"],
};
