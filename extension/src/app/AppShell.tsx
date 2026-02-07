"use client";

import { PropsWithChildren, useEffect } from "react";
import BottomNav from "@/components/BottomNav";
import TaskPoller from "@/wrapper/TaskPoller";
import { useSettingsStore } from "@/store/settings";
import { useQueueStorageSync } from "@/hooks/useQueueStorageSync";

export default function AppShell({ children }: PropsWithChildren) {
  useEffect(() => {
    void useSettingsStore.getState().hydrate();
  }, []);

  useQueueStorageSync();

  return (
    <div className="h-[600px] flex flex-col bg-background text-foreground">
      <main className="flex-1 overflow-y-auto">{children}</main>
      <BottomNav />
      <TaskPoller />
    </div>
  );
}
