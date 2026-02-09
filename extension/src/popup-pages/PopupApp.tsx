import { useCallback, useEffect, useState } from "react"
import BottomNav from "~/components/BottomNav"
import { useQueueStorageSync } from "~/hooks/useQueueStorageSync"
import { useSettingsStore } from "~/store/settings"
import TaskPoller from "~/wrapper/TaskPoller"
import AddPage from "~/popup-pages/AddPage"
import SettingsPage from "~/popup-pages/SettingsPage"
import TasksPage from "~/popup-pages/TasksPage"
import type { PopupRoute } from "~/popup-pages/types"

function hashToRoute(hash: string): PopupRoute {
  if (hash === "#/tasks") return "tasks"
  if (hash === "#/settings") return "settings"
  return "add"
}

function routeToHash(route: PopupRoute): string {
  if (route === "tasks") return "#/tasks"
  if (route === "settings") return "#/settings"
  return "#/"
}

export default function PopupApp() {
  const [route, setRoute] = useState<PopupRoute>(() => {
    if (typeof window === "undefined") return "add"
    return hashToRoute(window.location.hash)
  })

  useEffect(() => {
    void useSettingsStore.getState().hydrate()
  }, [])

  useQueueStorageSync()

  useEffect(() => {
    const onHashChange = () => {
      setRoute(hashToRoute(window.location.hash))
    }

    window.addEventListener("hashchange", onHashChange)
    return () => {
      window.removeEventListener("hashchange", onHashChange)
    }
  }, [])

  const navigate = useCallback((nextRoute: PopupRoute) => {
    const nextHash = routeToHash(nextRoute)
    if (window.location.hash === nextHash) {
      setRoute(nextRoute)
      return
    }
    window.location.hash = nextHash
  }, [])

  return (
    <div className="h-[600px] w-[380px] flex flex-col bg-background text-foreground">
      <main className="flex-1 overflow-y-auto">
        {route === "settings" ? (
          <SettingsPage navigate={navigate} />
        ) : route === "tasks" ? (
          <TasksPage navigate={navigate} />
        ) : (
          <AddPage navigate={navigate} />
        )}
      </main>
      <BottomNav route={route} onNavigate={navigate} />
      <TaskPoller />
    </div>
  )
}
