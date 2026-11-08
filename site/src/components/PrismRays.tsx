"use client";

import { useEffect, useRef } from "react";

/* Spectrum: [colour, end-y, breathe seconds, delay] */
const RAYS: ReadonlyArray<readonly [string, number, number, number]> = [
  ["#ff0055", 20, 3.4, 0],
  ["#ff5500", 140, 2.8, -0.7],
  ["#ffcc00", 260, 4, -1.5],
  ["#00ff66", 380, 3.2, -2.1],
  ["#00e5ff", 500, 2.9, -1],
  ["#2255ff", 620, 3.7, -2.6],
  ["#9900ff", 740, 3.1, -0.3],
];

/**
 * Fixed optical background: a white beam enters a prism and leaves as seven
 * spectral rays. Pure SVG and CSS (see theme-optics.css); the only script is a
 * small mouse-only parallax, throttled with requestAnimationFrame.
 */
export function PrismRays() {
  const ref = useRef<SVGSVGElement>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let raf = 0;
    let px = 0;
    let py = 0;

    const frame = () => {
      raf = 0;
      const nx = (px / window.innerWidth) * 2 - 1;
      const ny = (py / window.innerHeight) * 2 - 1;
      node.style.transform = `translate3d(${(-nx * 10).toFixed(1)}px,${(-ny * 8).toFixed(1)}px,0) scale(1.03)`;
    };

    const move = (event: PointerEvent) => {
      if (event.pointerType !== "mouse") return;
      px = event.clientX;
      py = event.clientY;
      raf = raf || window.requestAnimationFrame(frame);
    };

    const leave = () => {
      node.style.transform = "";
    };

    window.addEventListener("pointermove", move, { passive: true });
    document.documentElement.addEventListener("mouseleave", leave);

    return () => {
      window.removeEventListener("pointermove", move);
      document.documentElement.removeEventListener("mouseleave", leave);
      window.cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <svg
      ref={ref}
      className="optics"
      viewBox="0 0 1420 800"
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <linearGradient id="ox-body" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity=".07" />
          <stop offset="1" stopColor="#fff" stopOpacity=".01" />
        </linearGradient>
        <linearGradient id="ox-cone" x1="0" y1=".5" x2="1" y2=".5">
          <stop offset="0" stopColor="#fff" stopOpacity=".2" />
          <stop offset=".2" stopColor="#ff0055" stopOpacity=".15" />
          <stop offset=".5" stopColor="#00ff66" stopOpacity=".15" />
          <stop offset="1" stopColor="#9900ff" stopOpacity=".12" />
        </linearGradient>
        <filter id="ox-soft" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="8" />
        </filter>
        {/* userSpaceOnUse so perfectly horizontal lines are not clipped to a zero-height region */}
        <filter id="ox-blur" filterUnits="userSpaceOnUse" x="700" y="-100" width="900" height="1000">
          <feGaussianBlur stdDeviation="12" />
        </filter>
      </defs>

      <polygon points="785,400 1500,-50 1500,850" fill="url(#ox-cone)" opacity=".6" filter="url(#ox-soft)" />

      <g className="ox-rays">
        <g className="ox-glows" filter="url(#ox-blur)">
          {RAYS.map(([color, y]) => (
            <line key={color} className="ox-glow" x1="785" y1="400" x2="1500" y2={y} stroke={color} />
          ))}
        </g>
        <g>
          {RAYS.map(([color, y, seconds, delay]) => (
            <line
              key={color}
              className="ox-core"
              x1="785"
              y1="400"
              x2="1500"
              y2={y}
              stroke={color}
              style={{ animationDuration: `${seconds}s`, animationDelay: `${delay}s` }}
            />
          ))}
        </g>
      </g>

      <line className="ox-beam-core" pathLength={1} x1="635" y1="400" x2="785" y2="400" />
      <polygon
        points="710,220 560,580 860,580"
        fill="url(#ox-body)"
        stroke="rgba(255,255,255,.22)"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
      <line className="ox-beam-in" pathLength={1} x1="-100" y1="120" x2="635" y2="400" />
      <circle cx="635" cy="400" r="3" fill="#fff" opacity=".8" />
      <circle cx="785" cy="400" r="4" fill="#fff" opacity=".9" />
    </svg>
  );
}
