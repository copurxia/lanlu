/**
 * 菜单项分组工具函数
 * @module group-menu-items
 */

import type { MenuItem, MenuItemGroup } from "../unified-menu.types"

/**
 * 将菜单项按group属性分组
 * @param items - 菜单项数组
 * @returns 分组后的菜单项数组
 * @example
 * const grouped = groupMenuItems([
 *   { id: '1', label: 'Item 1', group: 'a' },
 *   { id: '2', label: 'Item 2', group: 'a' },
 *   { id: '3', label: 'Item 3', group: 'b' },
 * ])
 * // 返回: [{ id: 'a', items: [...] }, { id: 'b', items: [...] }]
 */
export function groupMenuItems(items: MenuItem[]): MenuItemGroup[] {
  const groups: Map<string | undefined, MenuItem[]> = new Map()

  // 按group属性分组
  for (const item of items) {
    const groupKey = item.group
    if (!groups.has(groupKey)) {
      groups.set(groupKey, [])
    }
    groups.get(groupKey)!.push(item)
  }

  // 转换为数组格式
  const result: MenuItemGroup[] = []
  groups.forEach((groupItems, groupId) => {
    result.push({
      id: groupId,
      items: groupItems,
    })
  })

  return result
}
