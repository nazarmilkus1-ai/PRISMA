"use client";

import * as React from "react";
import { Check, LoaderCircle, X } from "lucide-react";

export type PrismaProcessStep = {
  text: string;
};

type ProcessState = {
  steps: PrismaProcessStep[];
  duration: number;
  index: number;
  open: boolean;
  completed: boolean;
};

type ProcessNotificationContextValue = {
  start: (steps: PrismaProcessStep[], duration?: number) => void;
  dismiss: () => void;
};

const ProcessNotificationContext =
  React.createContext<ProcessNotificationContextValue | null>(null);

export function PrismaProcessNotificationProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const [state, setState] = React.useState<ProcessState | null>(null);

  const start = React.useCallback(
    (steps: PrismaProcessStep[], duration = 1600) => {
      const normalized = steps.filter((step) => step.text.trim().length > 0);
      if (!normalized.length) return;

      setState({
        steps: normalized,
        duration: Math.max(600, duration),
        index: 0,
        open: true,
        completed: false,
      });
    },
    [],
  );

  const dismiss = React.useCallback(() => {
    setState((current) => (current ? { ...current, open: false } : null));
  }, []);

  React.useEffect(() => {
    if (!state?.open || state.completed) return;

    if (state.index < state.steps.length - 1) {
      const timer = window.setTimeout(() => {
        setState((current) => {
          if (!current || !current.open || current.completed) return current;
          return { ...current, index: current.index + 1 };
        });
      }, state.duration);

      return () => window.clearTimeout(timer);
    }

    const timer = window.setTimeout(() => {
      setState((current) =>
        current ? { ...current, completed: true } : null,
      );
    }, state.duration);

    return () => window.clearTimeout(timer);
  }, [state]);

  React.useEffect(() => {
    if (!state?.completed) return;

    const timer = window.setTimeout(() => setState(null), 1400);
    return () => window.clearTimeout(timer);
  }, [state?.completed]);

  const currentStep = state?.steps[state.index];

  return (
    <ProcessNotificationContext.Provider value={{ start, dismiss }}>
      {children}

      {state?.open && currentStep ? (
        <aside
          className="prisma-process-notification"
          aria-live="polite"
          aria-atomic="true"
        >
          <div className="prisma-process-notification-glow" aria-hidden="true" />
          <div className="prisma-process-notification-border-glow" aria-hidden="true" />
          <div className="prisma-process-notification-surface" aria-hidden="true" />
          <div className="prisma-process-notification-icon" aria-hidden="true">
            {state.completed ? (
              <Check />
            ) : (
              <LoaderCircle className="prisma-process-notification-spinner" />
            )}
          </div>

          <div className="prisma-process-notification-content">
            <p className="prisma-process-notification-kicker">
              PRISMA / SYSTEM
            </p>
            <p className="prisma-process-notification-text">
              {state.completed ? "Готово" : currentStep.text}
            </p>

            <div
              className="prisma-process-notification-progress"
              aria-hidden="true"
            >
              {state.steps.map((step, index) => (
                <span
                  key={`${step.text}-${index}`}
                  className={index <= state.index ? "is-active" : undefined}
                />
              ))}
            </div>
          </div>

          <button
            type="button"
            className="prisma-process-notification-close"
            onClick={dismiss}
            aria-label="Закрыть уведомление"
          >
            <X />
          </button>
        </aside>
      ) : null}
    </ProcessNotificationContext.Provider>
  );
}

export function usePrismaProcessNotification() {
  const context = React.useContext(ProcessNotificationContext);

  if (!context) {
    throw new Error(
      "usePrismaProcessNotification must be used inside PrismaProcessNotificationProvider",
    );
  }

  return context;
}
