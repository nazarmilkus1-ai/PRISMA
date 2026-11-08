"use client";

import { useEffect, useState } from "react";
import { Icon } from "@/components/Icon";

const KEY = "prisma-theme";

export function ThemeSwitcher({ compact = false }: { compact?: boolean }) {
  const [dark, setDark] = useState(true);

  useEffect(() => {
    const saved = localStorage.getItem(KEY);
    const initial = saved === "light" ? false : true;

    setDark(initial);
    document.documentElement.classList.toggle("dark", initial);
  }, []);

  function toggle() {
    const next = !dark;
    setDark(next);
    localStorage.setItem(KEY, next ? "dark" : "light");
    document.documentElement.classList.toggle("dark", next);
  }

  return (
    <button
      type="button"
      onClick={toggle}
      title={dark ? "Светлая тема" : "Тёмная тема"}
      aria-label={dark ? "Светлая тема" : "Тёмная тема"}
      className={
        compact
          ? "inline-flex size-8 items-center justify-center rounded-md hover:bg-accent"
          : "inline-flex size-9 items-center justify-center rounded-md border bg-background hover:bg-accent"
      }
    >
      <Icon name={dark ? "sun" : "moon"} size={16} />
    </button>
  );
}
