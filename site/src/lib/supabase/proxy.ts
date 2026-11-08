import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest) {
  const requestHeaders = new Headers(request.headers);
  const path = request.nextUrl.pathname;
  requestHeaders.set("x-prisma-area", path === "/app" || path.startsWith("/app/") ? "participant" : "public");
  let response = NextResponse.next({ request: { headers: requestHeaders } });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value);
            response.cookies.set(name, value, options);
          });
        },
      },
    },
  );

  const { data, error } = await supabase.auth.getClaims();
  const hasUser = Boolean(!error && data?.claims?.sub);
  const protectedPath = path === "/app" || path.startsWith("/app/");
  const authPage = path === "/login";
  const publicVisitorPath =
    path === "/" ||
    path === "/apply" ||
    path === "/rules" ||
    path === "/wiki" ||
    path.startsWith("/wiki/") ||
    path === "/login" ||
    path.startsWith("/auth/") ||
    path.startsWith("/api/");

  // Unauthenticated visitors can only browse public Wiki pages and start an application.
  if (!hasUser && !publicVisitorPath) {
    const url = request.nextUrl.clone();
    url.pathname = "/";
    url.search = "";
    return NextResponse.redirect(url);
  }

  if (protectedPath && !hasUser) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  if (authPage && hasUser) {
    const url = request.nextUrl.clone();
    url.pathname = "/app";
    return NextResponse.redirect(url);
  }

  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
