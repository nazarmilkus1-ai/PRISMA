"use client";

import * as React from "react";

export type PrismaFloatingDockItem = {
  title: string;
  icon: React.ReactNode;
  href: string;
  external?: boolean;
  disabled?: boolean;
};

export interface PrismaFloatingDockProps
  extends React.HTMLAttributes<HTMLDivElement> {
  items: PrismaFloatingDockItem[];
  mobileClassName?: string;
  itemClassName?: string;
}

function joinClasses(...classes: Array<string | undefined | false>) {
  return classes.filter(Boolean).join(" ");
}

export function PrismaFloatingDock({
  items,
  className,
  mobileClassName,
  itemClassName,
  ...props
}: PrismaFloatingDockProps) {
  return (
    <div
      className={joinClasses("prisma-floating-dock-shell", className)}
      {...props}
    >
      <nav
        aria-label="PRISMA navigation"
        className={joinClasses(
          "prisma-floating-dock",
          mobileClassName,
        )}
      >
        {items.map((item) => {
          const isExternal =
            item.external ?? /^https?:\/\//i.test(item.href);

          return (
            <a
              key={item.title}
              href={item.disabled ? undefined : item.href}
              aria-label={item.title}
              aria-disabled={item.disabled || undefined}
              tabIndex={item.disabled ? -1 : undefined}
              target={isExternal ? "_blank" : undefined}
              rel={isExternal ? "noreferrer" : undefined}
              className={joinClasses(
                "prisma-floating-dock-item",
                item.disabled && "prisma-floating-dock-item-disabled",
                itemClassName,
              )}
            >
              <span
                aria-hidden="true"
                className="prisma-floating-dock-icon"
              >
                {item.icon}
              </span>

              <span className="prisma-floating-dock-tooltip">
                {item.title}
              </span>
            </a>
          );
        })}
      </nav>
    </div>
  );
}
