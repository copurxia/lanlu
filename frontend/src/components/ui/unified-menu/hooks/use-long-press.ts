/**
 * 长按检测Hook
 * 用于移动端右键菜单触发
 * @module use-long-press
 */

"use client"

import { useRef, useCallback } from "react"
import type { TouchEvent } from "react"

/**
 * 长按检测Hook配置
 */
interface UseLongPressOptions {
  /**
   * 长按阈值时间（毫秒）
   * @default 500
   */
  threshold?: number
}

/**
 * 长按检测Hook返回值
 */
interface UseLongPressReturn {
  onTouchStart: (event: TouchEvent) => void
  onTouchEnd: () => void
  onTouchMove: () => void
}

/**
 * 长按检测Hook
 * @param callback - 长按触发回调函数
 * @param options - 配置选项
 * @returns 触摸事件处理器
 * @example
 * const longPressHandlers = useLongPress(() => {
 *   console.log('Long press triggered!')
 * }, { threshold: 600 })
 *
 * <div {...longPressHandlers}>Long press me</div>
 */
export function useLongPress(
  callback: () => void,
  { threshold = 500 }: UseLongPressOptions = {}
): UseLongPressReturn {
  const timerRef = useRef<NodeJS.Timeout | undefined>(undefined)

  const start = useCallback(
    (_event: TouchEvent) => {
      void _event
      timerRef.current = setTimeout(callback, threshold)
    },
    [callback, threshold]
  )

  const stop = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current)
    }
  }, [])

  return {
    onTouchStart: start,
    onTouchEnd: stop,
    onTouchMove: stop,
  }
}
