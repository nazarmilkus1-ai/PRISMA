"use client";

import { useEffect } from "react";

/**
 * Feeds the black cursor glow of .prisma-glass-surface cards.
 * One passive listener for the whole page, mouse only, throttled to one write
 * per animation frame. Touch and reduced-motion users get the static state.
 */
export function GlassPointer() {
  useEffect(() => {
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let raf = 0;
    let last: PointerEvent | null = null;

    const frame = () => {
      raf = 0;
      if (!last) return;
      const target = last.target instanceof Element ? last.target : null;
      const surface = target?.closest<HTMLElement>(".prisma-glass-surface");
      if (!surface) return;
      const box = surface.getBoundingClientRect();
      surface.style.setProperty("--glass-mouse-x", `${(last.clientX - box.left).toFixed(0)}px`);
      surface.style.setProperty("--glass-mouse-y", `${(last.clientY - box.top).toFixed(0)}px`);
    };

    const move = (event: PointerEvent) => {
      if (event.pointerType !== "mouse") return;
      last = event;
      raf = raf || window.requestAnimationFrame(frame);
    };

    window.addEventListener("pointermove", move, { passive: true });
    return () => {
      window.removeEventListener("pointermove", move);
      window.cancelAnimationFrame(raf);
    };
  }, []);

  return null;
}
