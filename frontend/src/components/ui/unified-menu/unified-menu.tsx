/**
 * 统一菜单组件
 * 根据设备类型自动选择合适的展示方式
 * @module unified-menu
 */

"use client"

import * as React from "react"
import type { UnifiedMenuProps } from "./unified-menu.types"
import { useMediaQuery } from "./hooks/use-media-query"
import { groupMenuItems } from "./utils/group-menu-items"
import { DesktopMenuRenderer } from "./desktop-menu-renderer"
import { MobileMenuRenderer } from "./mobile-menu-renderer"

/**
 * 统一菜单组件
 * @param props - 组件属性
 * @returns 菜单组件
 * @example
 * // 基础使用
 * <UnifiedMenu
 *   items={[
 *     { id: 'edit', label: 'Edit', icon: Edit },
 *     { id: 'delete', label: 'Delete', icon: Trash2, danger: true },
 *   ]}
 *   onSelect={(id) => console.log(id)}
 * >
 *   <Button>Open Menu</Button>
 * </UnifiedMenu>
 *
 * // 右键菜单
 * <UnifiedMenu
 *   trigger="context-menu"
 *   items={contextMenuItems}
 *   onSelect={handleAction}
 * />
 *
 * // 移动端抽屉菜单
 * <UnifiedMenu
 *   title="Options"
 *   items={options}
 *   onSelect={handleOption}
 * />
 */
export function UnifiedMenu({
  items,
  trigger = "click",
  align = "start",
  title,
  subtitle,
  onSelect,
  onOpenChange,
  triggerElement,
  width = "auto",
  forceMode,
  children,
  open: controlledOpen,
  menuPosition: controlledMenuPosition,
}: UnifiedMenuProps) {
  // 状态管理（支持受控和非受控模式）
  const [internalOpen, setInternalOpen] = React.useState(false)
  const [internalMenuPosition, setInternalMenuPosition] = React.useState({ x: 0, y: 0 })

  // 使用受控值或内部状态
  const open = controlledOpen ?? internalOpen
  const menuPosition = controlledMenuPosition ?? internalMenuPosition
  const setOpen = React.useCallback(
    (newOpen: boolean) => {
      if (controlledOpen === undefined) {
        setInternalOpen(newOpen)
      }
    },
    [controlledOpen]
  )
  const setMenuPosition = React.useCallback(
    (newPosition: { x: number; y: number }) => {
      if (controlledMenuPosition === undefined) {
        setInternalMenuPosition(newPosition)
      }
    },
    [controlledMenuPosition]
  )

  // 响应式检测
  const isDesktop = useMediaQuery("(min-width: 768px)")
  const effectiveMode = forceMode ?? (isDesktop ? "desktop" : "mobile")

  // 菜单项分组处理
  const groupedItems = React.useMemo(() => groupMenuItems(items), [items])

  // 事件处理
  const handleSelect = React.useCallback(
    (id: string) => {
      onSelect?.(id)
      setOpen(false)
    },
    [onSelect, setOpen]
  )

  const handleOpenChange = React.useCallback(
    (newOpen: boolean) => {
      setOpen(newOpen)
      onOpenChange?.(newOpen)
    },
    [onOpenChange, setOpen]
  )

  // 右键菜单处理
  const handleContextMenu = React.useCallback(
    (event: React.MouseEvent) => {
      if (trigger === "context-menu") {
        event.preventDefault()
        setMenuPosition({ x: event.clientX, y: event.clientY })
        setOpen(true)
      }
    },
    [setMenuPosition, setOpen, trigger]
  )

  // 根据模式渲染不同组件
  if (effectiveMode === "desktop") {
    // 对于右键菜单，不需要外层div，直接渲染菜单内容
    if (trigger === "context-menu") {
      return (
        <DesktopMenuRenderer
          items={groupedItems}
          trigger={trigger}
          align={align}
          width={width}
          open={open}
          onOpenChange={handleOpenChange}
          onSelect={handleSelect}
          menuPosition={menuPosition}
          triggerElement={triggerElement}
          title={title}
          subtitle={subtitle}
        >
          {children}
        </DesktopMenuRenderer>
      )
    }

    return (
      <div onContextMenu={handleContextMenu}>
        <DesktopMenuRenderer
          items={groupedItems}
          trigger={trigger}
          align={align}
          width={width}
          open={open}
          onOpenChange={handleOpenChange}
          onSelect={handleSelect}
          menuPosition={menuPosition}
          triggerElement={triggerElement}
          title={title}
          subtitle={subtitle}
        >
          {children}
        </DesktopMenuRenderer>
      </div>
    )
  }

  return (
    <div onContextMenu={handleContextMenu}>
      <MobileMenuRenderer
        items={groupedItems}
        title={title}
        subtitle={subtitle}
        open={open}
        onOpenChange={handleOpenChange}
        onSelect={handleSelect}
        triggerElement={triggerElement}
      >
        {children}
      </MobileMenuRenderer>
    </div>
  )
}
