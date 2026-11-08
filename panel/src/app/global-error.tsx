"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="ru">
      <body>
        <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 24, background: "#050609", color: "#f8f8f8", fontFamily: "system-ui, sans-serif" }}>
          <div style={{ width: "100%", maxWidth: 560, border: "1px solid rgba(255,255,255,.12)", borderRadius: 18, padding: 28, background: "rgba(255,255,255,.05)", backdropFilter: "blur(18px)" }}>
            <p style={{ margin: 0, fontSize: 12, letterSpacing: ".14em", textTransform: "uppercase", opacity: .6 }}>PRISMA</p>
            <h2 style={{ margin: "10px 0 8px", fontSize: 24 }}>Произошла ошибка</h2>
            <p style={{ margin: 0, opacity: .7 }}>Служебная страница не смогла корректно загрузиться.</p>
            <button onClick={() => reset()} style={{ marginTop: 20, border: 0, borderRadius: 10, padding: "10px 14px", cursor: "pointer" }}>
              Попробовать ещё раз
            </button>
          </div>
        </main>
      </body>
    </html>
  );
}
