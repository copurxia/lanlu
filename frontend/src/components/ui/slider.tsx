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
  /** 已缓冲比例（0~1），用于显示缓冲进度层 */
  bufferedPercent?: number
}

const Slider = React.forwardRef<HTMLInputElement, SliderProps>(
  (
    { className, value = [0], onValueChange, max = 100, min = 0, step = 1, trackClassName, rangeClassName, bufferedPercent, ...props },
    ref
  ) => {
    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = [parseFloat(e.target.value)];
      onValueChange?.(newValue);
    };

    const clampedBuffered = bufferedPercent != null ? Math.max(0, Math.min(1, bufferedPercent)) : null;

    return (
      <div className={cn("relative flex w-full touch-none select-none items-center", className)}>
        <div
          className={cn(
            "relative h-2 w-full grow overflow-hidden rounded-full",
            progressSurfaceClassName,
            trackClassName
          )}
        >
          {clampedBuffered != null && (
            <div
              className="absolute h-full bg-black/25 dark:bg-white/20 transition-[width] duration-300 ease-out"
              style={{ width: `${clampedBuffered * 100}%` }}
            />
          )}
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
