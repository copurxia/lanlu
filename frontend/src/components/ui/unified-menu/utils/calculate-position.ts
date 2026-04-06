/**
 * 右键菜单位置计算工具函数
 * @module calculate-position
 */

/**
 * 计算右键菜单的最佳位置
 * 确保菜单不超出视口边界
 * @param clickX - 鼠标点击X坐标
 * @param clickY - 鼠标点击Y坐标
 * @param menuWidth - 菜单宽度
 * @param menuHeight - 菜单高度
 * @returns 计算后的菜单坐标
 * @example
 * const position = calculateMenuPosition(100, 200, 200, 300)
 * // 返回: { x: 100, y: 200 } 或调整后的位置
 */
export function calculateMenuPosition(
  clickX: number,
  clickY: number,
  menuWidth: number,
  menuHeight: number
): { x: number; y: number } {
  // SSR环境检查
  if (typeof window === "undefined") {
    return { x: clickX, y: clickY }
  }

  const viewportWidth = window.innerWidth
  const viewportHeight = window.innerHeight

  let x = clickX
  let y = clickY

  // 检查右边界
  if (x + menuWidth > viewportWidth) {
    x = viewportWidth - menuWidth - 8
  }

  // 检查下边界
  if (y + menuHeight > viewportHeight) {
    y = viewportHeight - menuHeight - 8
  }

  // 确保不超出左边界和上边界
  x = Math.max(8, x)
  y = Math.max(8, y)

  return { x, y }
}
