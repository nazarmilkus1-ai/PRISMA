import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { SiteHeader } from "@/components/SiteHeader";
import { PublicHeaderGate } from "@/components/PublicHeaderGate";
import { PrismRays } from "@/components/PrismRays";
import { GlassPointer } from "@/components/GlassPointer";
import { SiteFooter } from "@/components/SiteFooter";
import { AskWidget } from "@/components/AskWidget";
import { QuickNav } from "@/components/QuickNav";
import { PrismaProcessNotificationProvider } from "@/components/PrismaProcessNotification";
import "./globals.css";
import "./theme-optics.css";

export const metadata: Metadata = {
  title: { default: "PRISMA", template: "%s — PRISMA" },
  description: "Сообщество Minecraft-сервера PRISMA.",
  applicationName: "PRISMA",
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "https://prisma-fawn-seven.vercel.app"),
  icons: { icon: [{ url: "/favicon.svg", type: "image/svg+xml" }], apple: "/apple-icon" },
  openGraph: {
    type: "website",
    siteName: "PRISMA",
    title: "PRISMA",
    description: "Сообщество Minecraft-сервера PRISMA. Один луч, много цветов.",
    locale: "ru_RU",
  },
  twitter: { card: "summary_large_image", title: "PRISMA", description: "Сообщество Minecraft-сервера PRISMA." },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#030305",
};

export const dynamic = "force-dynamic";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const requestHeaders = await headers();
  const participant = requestHeaders.get("x-prisma-area") === "participant";

  return (
    <html lang="ru">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;600;700;800&display=swap"
        />
      </head>
      <body className="prisma-liquid-bg">
        {!participant ? (
          <a
            href="#content"
            className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-[100] focus:rounded-lg focus:bg-white focus:px-3 focus:py-2 focus:text-sm focus:font-bold focus:text-black"
          >
            К содержимому
          </a>
        ) : null}
        <QuickNav area={participant ? "participant" : "public"} />
        <PrismRays />
        <GlassPointer />
        <PrismaProcessNotificationProvider>
          {participant ? children : (
            <>
              <PublicHeaderGate>
                <SiteHeader />
              </PublicHeaderGate>
              <main id="content" className="relative z-10 prisma-page-enter min-h-[calc(100vh-64px)]">{children}</main>
              <SiteFooter />
              <AskWidget />
            </>
          )}
        </PrismaProcessNotificationProvider>
      </body>
    </html>
  );
}
