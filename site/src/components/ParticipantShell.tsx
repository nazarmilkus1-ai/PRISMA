"use client";

import { useState } from "react";
import { ParticipantHeader } from "@/components/ParticipantHeader";
import { ParticipantSidebar } from "@/components/ParticipantSidebar";
import type { ModuleEnabledMap } from "@prisma-eco/contracts";

type UserSummary = {
  minecraft_nickname?: string | null;
  first_name?: string | null;
  telegram_username?: string | null;
  status?: string | null;
  is_banned?: boolean;
  is_whitelisted?: boolean;
};

export function ParticipantShell({
  user,
  notificationsCount = 0,
  enabledModules,
  children,
}: {
  user: UserSummary;
  notificationsCount?: number;
  enabledModules: ModuleEnabledMap;
  children: React.ReactNode;
}) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  return (
    <div data-prisma-participant className="relative z-10 flex min-h-svh w-full bg-transparent">
      <a href="#participant-content" className="skip-link">
        Перейти к содержимому
      </a>

      {mobileOpen && (
        <button
          type="button"
          aria-label="Закрыть меню"
          className="fixed inset-0 z-40 bg-overlay md:hidden"
          onClick={() => setMobileOpen(false)}
        />
      )}

      <ParticipantSidebar
        collapsed={collapsed}
        mobileOpen={mobileOpen}
        onMobileClose={() => setMobileOpen(false)}
        notificationsCount={notificationsCount}
        enabledModules={enabledModules}
        canUseMarket={Boolean(user.status === "ACCEPTED" && !user.is_banned && user.is_whitelisted)}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <ParticipantHeader
          user={user}
          onMenuToggle={() => {
            if (window.innerWidth < 768) setMobileOpen(true);
            else setCollapsed((value) => !value);
          }}
        />

        <main
          id="participant-content"
          className="mx-auto flex w-full max-w-[1200px] flex-1 flex-col px-4 py-6 sm:px-6 lg:px-8"
        >
          {children}
        </main>
      </div>
    </div>
  );
}
