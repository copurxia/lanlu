"use client"

import * as React from "react"

import { progressFillClassName, progressSurfaceClassName } from "@/components/ui/progress-theme"
import { cn } from "@/lib/utils/utils"

interface SliderProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> {
  value?: number[]
  onValueChange?: (value: number[]) => void
  max?: number
  min?: number
  step?: number
  trackClassName?: string
  rangeClassName?: string
}

const Slider = React.forwardRef<HTMLInputElement, SliderProps>(
  (
    { className, value = [0], onValueChange, max = 100, min = 0, step = 1, trackClassName, rangeClassName, ...props },
    ref
  ) => {
    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = [parseFloat(e.target.value)];
      onValueChange?.(newValue);
    };

    return (
      <div className={cn("relative flex w-full touch-none select-none items-center", className)}>
        <div
          className={cn(
            "relative h-2 w-full grow overflow-hidden rounded-full",
            progressSurfaceClassName,
            trackClassName
          )}
        >
          <div 
            className={cn("absolute h-full", progressFillClassName, rangeClassName)}
            style={{ width: `${((value[0] - min) / (max - min)) * 100}%` }}
          />
        </div>
        <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={value[0]}
          onChange={handleChange}
          className="absolute inset-0 h-full w-full cursor-pointer opacity-0"
          ref={ref}
          {...props}
        />
      </div>
    )
  }
)
Slider.displayName = "Slider"

export { Slider }
