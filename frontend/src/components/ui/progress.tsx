"use client"

import * as React from "react"

import { progressFillClassName, progressSurfaceClassName } from "@/components/ui/progress-theme"
import { cn } from "@/lib/utils/utils"

interface ProgressProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: number
}

const Progress = React.forwardRef<HTMLDivElement, ProgressProps>(
  ({ className, value, ...props }, ref) => (
    <div
      ref={ref}
      className={cn(
        "relative h-2 w-full overflow-hidden rounded-full",
        progressSurfaceClassName,
        className
      )}
      {...props}
    >
      <div
        className={cn(
          "h-full transition-all duration-300 ease-in-out",
          progressFillClassName
        )}
        style={{ width: `${value || 0}%` }}
      />
    </div>
  )
)
Progress.displayName = "Progress"

export { Progress }
