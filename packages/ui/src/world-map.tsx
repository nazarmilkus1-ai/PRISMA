"use client";

import * as React from "react";

export type PrismaWorldMapPoint = {
  id?: string;
  start: { lat: number; lng: number };
  end: { lat: number; lng: number };
};

export interface PrismaWorldMapProps
  extends React.HTMLAttributes<HTMLDivElement> {
  points: PrismaWorldMapPoint[];
  title?: string;
  subtitle?: string;
  className?: string;
}

function project(lat: number, lng: number) {
  return {
    x: 5 + ((lng + 180) / 360) * 90,
    y: 8 + ((90 - lat) / 180) * 84,
  };
}

function curvePath(
  start: { lat: number; lng: number },
  end: { lat: number; lng: number },
) {
  const a = project(start.lat, start.lng);
  const b = project(end.lat, end.lng);
  const midX = (a.x + b.x) / 2;
  const distance = Math.abs(b.x - a.x);
  const lift = Math.min(22, 7 + distance * 0.16);

  return `M ${a.x.toFixed(2)} ${a.y.toFixed(2)} Q ${midX.toFixed(2)} ${(
    Math.min(a.y, b.y) - lift
  ).toFixed(2)} ${b.x.toFixed(2)} ${b.y.toFixed(2)}`;
}

export function PrismaWorldMap({
  points,
  title = "PRISMA Network",
  subtitle = "Связи сообщества и серверной инфраструктуры",
  className,
  ...props
}: PrismaWorldMapProps) {
  return (
    <section
      className={`prisma-world-map ${className ?? ""}`.trim()}
      {...props}
    >
      <div className="prisma-world-map-header">
        <div>
          <p className="prisma-world-map-eyebrow">PRISMA / NETWORK</p>
          <h2 className="prisma-world-map-title">{title}</h2>
          <p className="prisma-world-map-subtitle">{subtitle}</p>
        </div>
        <div className="prisma-world-map-status">
          <span />
          LIVE
        </div>
      </div>

      <div className="prisma-world-map-canvas">
        <svg
          viewBox="0 0 100 100"
          role="img"
          aria-label="PRISMA network world map"
        >
          <defs>
            <radialGradient id="prisma-map-glow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="currentColor" stopOpacity=".16" />
              <stop offset="100%" stopColor="currentColor" stopOpacity="0" />
            </radialGradient>
            <linearGradient id="prisma-map-line" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="var(--success)" stopOpacity=".16" />
              <stop offset="50%" stopColor="var(--foreground-contrast)" stopOpacity=".72" />
              <stop offset="100%" stopColor="var(--success)" stopOpacity=".16" />
            </linearGradient>
          </defs>

          <rect width="100" height="100" fill="transparent" />

          <g className="prisma-world-map-grid" aria-hidden="true">
            {Array.from({ length: 7 }).map((_, index) => {
              const y = 10 + index * 13.2;
              return <line key={`h-${index}`} x1="4" x2="96" y1={y} y2={y} />;
            })}
            {Array.from({ length: 9 }).map((_, index) => {
              const x = 5 + index * 11.25;
              return <line key={`v-${index}`} x1={x} x2={x} y1="7" y2="93" />;
            })}
          </g>

          <g className="prisma-world-map-land" aria-hidden="true">
            <path d="M18 27 23 20 32 19 38 24 35 31 29 34 24 31 18 35 14 32Z" />
            <path d="M31 43 36 42 40 48 38 58 33 67 29 60 30 52 27 47Z" />
            <path d="M48 23 57 20 64 24 70 22 78 27 83 24 88 30 84 35 78 34 75 40 68 39 64 34 57 36 54 30 48 31 44 27Z" />
            <path d="M66 44 73 43 77 48 74 57 69 63 65 58 67 52 62 48Z" />
            <path d="M80 62 87 64 90 69 86 75 80 72 77 67Z" />
          </g>

          <g className="prisma-world-map-routes">
            {points.map((point, index) => {
              const a = project(point.start.lat, point.start.lng);
              const b = project(point.end.lat, point.end.lng);
              const path = curvePath(point.start, point.end);

              return (
                <g key={point.id ?? `route-${index}`}>
                  <path d={path} className="prisma-world-map-route-shadow" />
                  <path
                    d={path}
                    pathLength="1"
                    className="prisma-world-map-route"
                    style={{ animationDelay: `${index * -0.8}s` }}
                  />
                  <circle cx={a.x} cy={a.y} r="1.15" className="prisma-world-map-node" />
                  <circle cx={b.x} cy={b.y} r="1.15" className="prisma-world-map-node" />
                </g>
              );
            })}
          </g>
        </svg>

        <div className="prisma-world-map-scanline" aria-hidden="true" />
      </div>

      <div className="prisma-world-map-footer">
        <span>{points.length} active connections</span>
        <span>PRISMA Ecosystem</span>
      </div>
    </section>
  );
}
