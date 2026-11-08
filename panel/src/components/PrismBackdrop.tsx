"use client";

import { useEffect, useRef } from "react";

export function PrismBackdrop() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;

    let raf = 0;
    let targetX = 0;
    let targetY = 0;
    let currentX = 0;
    let currentY = 0;

    const move = (event: PointerEvent) => {
      targetX = event.clientX / window.innerWidth - 0.5;
      targetY = event.clientY / window.innerHeight - 0.5;
    };

    const render = () => {
      currentX += (targetX - currentX) * 0.035;
      currentY += (targetY - currentY) * 0.035;
      node.style.setProperty("--mx", currentX.toFixed(4));
      node.style.setProperty("--my", currentY.toFixed(4));
      raf = window.requestAnimationFrame(render);
    };

    window.addEventListener("pointermove", move, { passive: true });
    raf = window.requestAnimationFrame(render);
    return () => {
      window.removeEventListener("pointermove", move);
      window.cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <div ref={ref} aria-hidden="true" className="pointer-events-none fixed inset-0 z-0 overflow-hidden [--mx:0] [--my:0]">
      <svg viewBox="0 0 1600 900" preserveAspectRatio="xMidYMid slice" className="absolute inset-0 h-full w-full opacity-65">
        <defs>
          <linearGradient id="panel-prism-spectrum" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#ff5366"/><stop offset="20%" stopColor="#ffad4d"/>
            <stop offset="40%" stopColor="#ffe35d"/><stop offset="60%" stopColor="#49dd99"/>
            <stop offset="80%" stopColor="#52a8ff"/><stop offset="100%" stopColor="#b975ff"/>
          </linearGradient>
          <linearGradient id="panel-prism-edge" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#ffffff" stopOpacity=".82"/>
            <stop offset="50%" stopColor="#c9edff" stopOpacity=".34"/>
            <stop offset="100%" stopColor="#ffffff" stopOpacity=".7"/>
          </linearGradient>
          <filter id="panel-prism-glow" x="-60%" y="-60%" width="220%" height="220%">
            <feGaussianBlur stdDeviation="9" result="blur"/>
            <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
          </filter>
          <radialGradient id="panel-prism-halo">
            <stop offset="0%" stopColor="#54dfa0" stopOpacity=".13"/>
            <stop offset="55%" stopColor="#559dff" stopOpacity=".045"/>
            <stop offset="100%" stopColor="#559dff" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <g style={{transform:"translate(calc(var(--mx) * 18px), calc(var(--my) * 12px))"}}>
          <ellipse cx="910" cy="470" rx="490" ry="275" fill="url(#panel-prism-halo)"/>
          <path d="M-520 450 H710" stroke="#fff" strokeWidth="16" opacity=".045" filter="url(#panel-prism-glow)"/>
          <path d="M-520 450 H710" stroke="#fff" strokeWidth="1.8" opacity=".48"/>
          <polygon points="710,305 710,595 995,450" fill="#ffffff" fillOpacity=".022" stroke="url(#panel-prism-edge)" strokeWidth="1.8" strokeLinejoin="round"/>
          <path d="M748 330 L748 530 M740 346 L980 450 L740 554 Z" fill="none" stroke="#fff" strokeOpacity=".1" strokeWidth="1"/>
          <g fill="none" strokeLinecap="round" filter="url(#panel-prism-glow)">
            <path d="M995 450 L2120 528" stroke="#ff5366" strokeWidth="8" opacity=".045"/>
            <path d="M995 450 L2120 568" stroke="#ffad4d" strokeWidth="8" opacity=".042"/>
            <path d="M995 450 L2120 608" stroke="#ffe35d" strokeWidth="8" opacity=".04"/>
            <path d="M995 450 L2120 648" stroke="#49dd99" strokeWidth="8" opacity=".038"/>
            <path d="M995 450 L2120 688" stroke="#52a8ff" strokeWidth="8" opacity=".036"/>
            <path d="M995 450 L2120 728" stroke="#b975ff" strokeWidth="8" opacity=".034"/>
          </g>
          <g fill="none" strokeLinecap="round">
            <path d="M995 450 L2120 528" stroke="#ff5366" strokeWidth="1.5" opacity=".34"/>
            <path d="M995 450 L2120 568" stroke="#ffad4d" strokeWidth="1.45" opacity=".32"/>
            <path d="M995 450 L2120 608" stroke="#ffe35d" strokeWidth="1.4" opacity=".3"/>
            <path d="M995 450 L2120 648" stroke="#49dd99" strokeWidth="1.35" opacity=".3"/>
            <path d="M995 450 L2120 688" stroke="#52a8ff" strokeWidth="1.3" opacity=".28"/>
            <path d="M995 450 L2120 728" stroke="#b975ff" strokeWidth="1.25" opacity=".27"/>
            <path d="M995 450 L2120 648" stroke="url(#panel-prism-spectrum)" strokeWidth=".55" opacity=".45"/>
          </g>
          <circle cx="995" cy="450" r="5.5" fill="#fff" opacity=".7" filter="url(#panel-prism-glow)"/>
        </g>
      </svg>
    </div>
  );
}
