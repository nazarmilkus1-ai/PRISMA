"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { postForm, toast } from "@/lib/optimistic";

/**
 * On/off switch that flips instantly and saves in the background. Failure flips it back and tells the user.
 * Posts `{ fieldName: key, valueName: "true" | "false" }` to `action`.
 */
export function OptimisticToggle({
  action,
  fieldName = "key",
  valueName = "value",
  itemKey,
  initialOn,
  onLabel = "Включено",
  offLabel = "Выключено",
  className = "",
  onClassName = "",
  offClassName = "",
}: {
  action: string;
  fieldName?: string;
  valueName?: string;
  itemKey: string;
  initialOn: boolean;
  onLabel?: string;
  offLabel?: string;
  className?: string;
  onClassName?: string;
  offClassName?: string;
}) {
  const router = useRouter();
  const [on, setOn] = useState(initialOn);
  const [saving, setSaving] = useState(false);
  const [, startTransition] = useTransition();

  async function flip() {
    if (saving) return;
    const next = !on;
    setOn(next);
    setSaving(true);
    const body = new FormData();
    body.set(fieldName, itemKey);
    body.set(valueName, String(next));
    const result = await postForm(action, body);
    setSaving(false);
    if (!result.ok) {
      setOn(!next);
      toast(result.message || "Не удалось сохранить настройку.", "err");
      return;
    }
    startTransition(() => router.refresh());
  }

  return (
    <button
      type="button"
      onClick={flip}
      aria-pressed={on}
      className={[className, on ? onClassName : offClassName, saving ? "opacity-80" : ""].join(" ")}
    >
      {on ? onLabel : offLabel}
    </button>
  );
}
