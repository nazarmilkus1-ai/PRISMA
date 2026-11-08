export type ThemePreference = "dark" | "oled" | "light" | "system" | "custom";
export type ResolvedTheme = "dark" | "oled" | "light" | "custom";

export const THEME_STORAGE_KEY = "prisma-theme";
export const CUSTOM_THEME_STORAGE_KEY = "prisma-theme-custom";

export type CustomTheme = {
  void: string;
  panel: string;
  island: string;
  panelRaised: string;
  border: string;
  accent: string;
  moon: string;
};

export const DEFAULT_CUSTOM_THEME: CustomTheme = {
  void: "#070908",
  panel: "#101210",
  island: "#171a18",
  panelRaised: "#1d211f",
  border: "#303532",
  accent: "#45e0a0",
  moon: "#f5f7f8",
};

export const THEME_OPTIONS: { value: ThemePreference; label: string; icon: string }[] = [
  { value: "dark", label: "Тёмная", icon: "🌙" },
  { value: "oled", label: "OLED", icon: "⚫" },
  { value: "light", label: "Светлая", icon: "☀️" },
  { value: "system", label: "Системная", icon: "🖥" },
  { value: "custom", label: "Custom", icon: "🎨" },
];

export function systemPrefersDark(): boolean {
  if (typeof window === "undefined") return true;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

export function resolveTheme(pref: ThemePreference): ResolvedTheme {
  if (pref === "system") return systemPrefersDark() ? "dark" : "light";
  return pref;
}

export function getCustomTheme(): CustomTheme {
  if (typeof window === "undefined") return DEFAULT_CUSTOM_THEME;
  try {
    const parsed = JSON.parse(localStorage.getItem(CUSTOM_THEME_STORAGE_KEY) || "");
    return parsed && typeof parsed === "object" ? { ...DEFAULT_CUSTOM_THEME, ...parsed } : DEFAULT_CUSTOM_THEME;
  } catch {
    return DEFAULT_CUSTOM_THEME;
  }
}

function applyCustomTheme(root: HTMLElement, c: CustomTheme) {
  root.style.setProperty("--color-void", c.void);
  root.style.setProperty("--color-panel", c.panel);
  root.style.setProperty("--color-island", c.island);
  root.style.setProperty("--color-panel-raised", c.panelRaised);
  root.style.setProperty("--color-border", c.border);
  root.style.setProperty("--color-ember", c.accent);
  root.style.setProperty("--color-curse", c.accent);
  root.style.setProperty("--color-moon", c.moon);

  root.style.setProperty("--background", c.void);
  root.style.setProperty("--foreground", c.moon);
  root.style.setProperty("--card", c.island);
  root.style.setProperty("--sidebar", c.panel);
  root.style.setProperty("--sidebar-foreground", c.moon);
  root.style.setProperty("--muted", c.panelRaised);
  root.style.setProperty("--muted-foreground", c.moon);
  root.style.setProperty("--accent", c.panelRaised);
  root.style.setProperty("--accent-foreground", c.moon);
  root.style.setProperty("--primary", c.accent);
  root.style.setProperty("--primary-strong", c.accent);
  root.style.setProperty("--primary-foreground", c.void);
  root.style.setProperty("--secondary", c.island);
  root.style.setProperty("--secondary-foreground", c.moon);
  root.style.setProperty("--input", c.panelRaised);
  root.style.setProperty("--ring", c.accent);
}

function clearCustomTheme(root: HTMLElement) {
  [
    "--color-void",
    "--color-panel",
    "--color-island",
    "--color-panel-raised",
    "--color-border",
    "--color-ember",
    "--color-curse",
    "--color-moon",
    "--background",
    "--foreground",
    "--card",
    "--sidebar",
    "--sidebar-foreground",
    "--muted",
    "--muted-foreground",
    "--accent",
    "--accent-foreground",
    "--primary",
    "--primary-strong",
    "--primary-foreground",
    "--secondary",
    "--secondary-foreground",
    "--input",
    "--ring",
  ].forEach((v) => root.style.removeProperty(v));
}

export function applyTheme(pref: ThemePreference) {
  const root = document.documentElement;
  root.setAttribute("data-theme", resolveTheme(pref));
  clearCustomTheme(root);

  if (pref === "custom") {
    applyCustomTheme(root, getCustomTheme());
  }
}

export const NO_FLASH_THEME_SCRIPT = `
(function(){
  try {
    var s = localStorage.getItem("${THEME_STORAGE_KEY}") || "system";
    var r = s === "system"
      ? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
      : s;
    document.documentElement.setAttribute("data-theme", r);

    if (r === "custom") {
      var c = JSON.parse(localStorage.getItem("${CUSTOM_THEME_STORAGE_KEY}") || "{}");
      var d = ${JSON.stringify(DEFAULT_CUSTOM_THEME)};
      c = Object.assign(d, c);
      var root = document.documentElement;
      root.style.setProperty("--color-void", c.void);
      root.style.setProperty("--color-panel", c.panel);
      root.style.setProperty("--color-island", c.island);
      root.style.setProperty("--color-panel-raised", c.panelRaised);
      root.style.setProperty("--color-border", c.border);
      root.style.setProperty("--color-ember", c.accent);
      root.style.setProperty("--color-curse", c.accent);
      root.style.setProperty("--color-moon", c.moon);
      root.style.setProperty("--background", c.void);
      root.style.setProperty("--foreground", c.moon);
      root.style.setProperty("--card", c.island);
      root.style.setProperty("--sidebar", c.panel);
      root.style.setProperty("--sidebar-foreground", c.moon);
      root.style.setProperty("--muted", c.panelRaised);
      root.style.setProperty("--muted-foreground", c.moon);
      root.style.setProperty("--accent", c.panelRaised);
      root.style.setProperty("--accent-foreground", c.moon);
      root.style.setProperty("--primary", c.accent);
      root.style.setProperty("--primary-strong", c.accent);
      root.style.setProperty("--primary-foreground", c.void);
      root.style.setProperty("--secondary", c.island);
      root.style.setProperty("--secondary-foreground", c.moon);
      root.style.setProperty("--input", c.panelRaised);
      root.style.setProperty("--ring", c.accent);
    }
  } catch (e) {}
})();
`;
