import type { PopupRoute } from "~/popup-pages/types"

type BottomNavProps = {
  route: PopupRoute
  onNavigate: (route: PopupRoute) => void
}

const items: Array<{ route: PopupRoute; label: string }> = [
  { route: "add", label: "添加" },
  { route: "tasks", label: "任务" },
  { route: "settings", label: "设置" }
]

export default function BottomNav({ route, onNavigate }: BottomNavProps) {
  return (
    <nav className="h-12 border-t bg-card text-card-foreground flex items-stretch">
      {items.map((it) => {
        const active = route === it.route
        return (
          <button
            key={it.route}
            type="button"
            className={[
              "flex-1 flex items-center justify-center text-sm",
              active
                ? "text-foreground font-medium"
                : "text-muted-foreground hover:text-foreground"
            ].join(" ")}
            onClick={() => onNavigate(it.route)}>
            {it.label}
          </button>
        )
      })}
    </nav>
  )
}
