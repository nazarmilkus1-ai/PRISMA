"use client";

import * as React from "react";
import { cn } from "@prisma-eco/ui";

type PlayerSuggestion = {
  id: string;
  minecraft_nickname: string;
  platform: "JAVA" | "BEDROCK" | null;
  rating: number;
  activity_score: number;
};

type Props = React.InputHTMLAttributes<HTMLInputElement>;

export function MinecraftNicknameAutocomplete({
  className,
  id,
  defaultValue,
  ...props
}: Props) {
  const inputId = id ?? "minecraft-nickname";
  const [suggestions, setSuggestions] = React.useState<PlayerSuggestion[]>([]);
  const [open, setOpen] = React.useState(false);
  const [activeIndex, setActiveIndex] = React.useState(-1);
  const [loading, setLoading] = React.useState(false);
  const [query, setQuery] = React.useState(String(defaultValue ?? ""));
  const requestId = React.useRef(0);
  const inputRef = React.useRef<HTMLInputElement>(null);

  React.useEffect(() => {
    const normalized = query.trim();

    if (normalized.length < 1) {
      setSuggestions([]);
      setOpen(false);
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    const currentRequest = ++requestId.current;
    const timer = window.setTimeout(async () => {
      setLoading(true);

      try {
        const response = await fetch(
          "/api/players/suggestions?q=" + encodeURIComponent(normalized),
          {
            method: "GET",
            headers: { Accept: "application/json" },
            cache: "no-store",
            signal: controller.signal,
          },
        );

        if (!response.ok) throw new Error("suggestions_failed");

        const payload = (await response.json()) as {
          players?: PlayerSuggestion[];
        };

        if (currentRequest !== requestId.current) return;

        const next = Array.isArray(payload.players) ? payload.players : [];
        setSuggestions(next);
        setActiveIndex(-1);
        setOpen(next.length > 0);
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") return;
        if (currentRequest !== requestId.current) return;
        setSuggestions([]);
        setOpen(false);
      } finally {
        if (currentRequest === requestId.current) setLoading(false);
      }
    }, 180);

    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [query]);

  function selectSuggestion(player: PlayerSuggestion) {
    const input = inputRef.current;
    if (!input) return;

    input.value = player.minecraft_nickname;
    setQuery(player.minecraft_nickname);
    setOpen(false);
    setActiveIndex(-1);
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (!open || !suggestions.length) {
      props.onKeyDown?.(event);
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((current) => (current + 1) % suggestions.length);
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((current) => (current <= 0 ? suggestions.length - 1 : current - 1));
      return;
    }

    if (event.key === "Enter" && activeIndex >= 0) {
      event.preventDefault();
      selectSuggestion(suggestions[activeIndex]);
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      setOpen(false);
      setActiveIndex(-1);
      return;
    }

    props.onKeyDown?.(event);
  }

  return (
    <div className="relative">
      <input
        {...props}
        ref={inputRef}
        id={inputId}
        defaultValue={defaultValue}
        onChange={(event) => {
          setQuery(event.currentTarget.value);
          props.onChange?.(event);
        }}
        onKeyDown={handleKeyDown}
        onFocus={() => suggestions.length > 0 && setOpen(true)}
        onBlur={() => window.setTimeout(() => setOpen(false), 120)}
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={open}
        aria-controls={open ? inputId + "-suggestions" : undefined}
        aria-activedescendant={
          open && activeIndex >= 0
            ? inputId + "-suggestion-" + activeIndex
            : undefined
        }
        className={cn("w-full", className)}
      />

      {open ? (
        <div
          id={inputId + "-suggestions"}
          role="listbox"
          className="prisma-glass-surface absolute left-0 right-0 top-[calc(100%+0.4rem)] z-50 overflow-hidden rounded-xl border p-1 shadow-2xl"
        >
          {suggestions.map((player, index) => (
            <button
              key={player.id}
              id={inputId + "-suggestion-" + index}
              type="button"
              role="option"
              aria-selected={index === activeIndex}
              className={cn(
                "flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left transition-colors",
                index === activeIndex
                  ? "bg-white/[0.08]"
                  : "hover:bg-white/[0.05]",
              )}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => selectSuggestion(player)}
            >
              <span className="min-w-0">
                <span className="block truncate text-sm font-medium">
                  {player.minecraft_nickname}
                </span>
                <span className="mt-0.5 block text-[11px] text-muted-foreground">
                  {player.platform === "BEDROCK" ? "BEDROCK" : "JAVA"} · RR {player.rating} · Activity {player.activity_score}
                </span>
              </span>
            </button>
          ))}
        </div>
      ) : null}

      {loading && query.trim().length > 0 ? (
        <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-[10px] text-muted-foreground">
          …
        </span>
      ) : null}
    </div>
  );
}
