/**
 * 媒体查询Hook
 * 用于检测设备类型和屏幕尺寸
 * @module use-media-query
 */

"use client"

import { useState, useEffect } from "react"

/**
 * 媒体查询Hook
 * @param query - 媒体查询字符串
 * @returns 是否匹配的布尔值
 * @example
 * const isDesktop = useMediaQuery('(min-width: 768px)')
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false)

  useEffect(() => {
    // SSR环境检查
    if (typeof window === "undefined") return

    const media = window.matchMedia(query)
    setMatches(media.matches)

    const listener = (event: MediaQueryListEvent) => {
      setMatches(event.matches)
    }

    media.addEventListener("change", listener)
    return () => media.removeEventListener("change", listener)
  }, [query])

  return matches
}
