"use client";
import { useEffect } from "react";
import { createPortal } from "react-dom";

export function Modal({
  open,
  onClose,
  children,
}: {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
}) {
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-void/80 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full max-w-md rounded-xl border border-border bg-panel p-6 shadow-2xl">
        {children}
      </div>
    </div>,
    document.body,
  );
}

const CONFIRM_TONE_STYLES: Record<string, string> = {
  ember: "bg-ember/20 text-ember hover:bg-ember/30",
  danger: "bg-danger/20 text-danger hover:bg-danger/30",
  success: "bg-success/20 text-success hover:bg-success/30",
};

export function ConfirmModal({
  open,
  onClose,
  onConfirm,
  title,
  description,
  confirmLabel = "Подтвердить",
  tone = "ember",
  busy,
  children,
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  description?: string;
  confirmLabel?: string;
  tone?: "ember" | "danger" | "success";
  busy?: boolean;
  children?: React.ReactNode;
}) {
  return (
    <Modal open={open} onClose={onClose}>
      <h2 className="font-display text-lg text-moon">{title}</h2>
      {description && <p className="mt-2 text-sm text-moon-dim">{description}</p>}
      {children && <div className="mt-4">{children}</div>}
      <div className="mt-6 flex justify-end gap-2">
        <button
          onClick={onClose}
          className="rounded-lg border border-border px-4 py-2 text-sm text-moon-dim transition-colors hover:bg-panel-raised hover:text-moon"
        >
          Отмена
        </button>
        <button
          onClick={onConfirm}
          disabled={busy}
          className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors disabled:opacity-40 ${CONFIRM_TONE_STYLES[tone]}`}
        >
          {busy ? "Выполняется…" : confirmLabel}
        </button>
      </div>
    </Modal>
  );
}
