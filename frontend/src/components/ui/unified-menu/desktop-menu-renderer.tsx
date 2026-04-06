/**
 * 桌面端菜单渲染器
 * @module desktop-menu-renderer
 */

"use client"

import * as React from "react"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
  DropdownMenuShortcut,
} from "@/components/ui/dropdown-menu"
import { cn } from "@/lib/utils/utils"
import { ChevronRight } from "lucide-react"
import type { DesktopMenuRendererProps, MenuItem, MenuItemGroup } from "./unified-menu.types"
import { menuItemVariants } from "./styles/menu-item-variants"

/**
 * 子菜单渲染器
 */
function SubMenuItemRenderer({
  item,
  onSelect,
}: {
  item: MenuItem
  onSelect: (id: string) => void
}) {
  if (!item.children) return null

  return (
    <DropdownMenuSub>
      <DropdownMenuSubTrigger
        disabled={item.disabled}
        className={cn(item.danger && "text-destructive focus:text-destructive")}
      >
        {item.icon && <item.icon className="mr-2 h-4 w-4" />}
        <span>{item.label}</span>
      </DropdownMenuSubTrigger>
      <DropdownMenuSubContent>
        {item.children.map((child) => (
          <React.Fragment key={child.id}>
            {child.separator && <DropdownMenuSeparator />}
            {child.children ? (
              <SubMenuItemRenderer item={child} onSelect={onSelect} />
            ) : (
              <DropdownMenuItem
                disabled={child.disabled}
                className={cn(child.danger && "text-destructive focus:text-destructive")}
                onSelect={() => {
                  if (child.onClick) {
                    void child.onClick()
                  } else {
                    onSelect(child.id)
                  }
                }}
              >
                {child.icon && <child.icon className="mr-2 h-4 w-4" />}
                <span>{child.label}</span>
                {child.shortcut && <DropdownMenuShortcut>{child.shortcut}</DropdownMenuShortcut>}
              </DropdownMenuItem>
            )}
          </React.Fragment>
        ))}
      </DropdownMenuSubContent>
    </DropdownMenuSub>
  )
}

/**
 * 菜单组渲染器
 */
function MenuItemGroupRenderer({
  group,
  onSelect,
  isLastGroup,
}: {
  group: MenuItemGroup
  onSelect: (id: string) => void
  isLastGroup: boolean
}) {
  return (
    <>
      {group.items.map((item) => (
        <React.Fragment key={item.id}>
          {item.separator && <DropdownMenuSeparator />}
          {item.customRender ? (
            item.customRender(item, () => onSelect(item.id))
          ) : item.children ? (
            <SubMenuItemRenderer item={item} onSelect={onSelect} />
          ) : (
            <DropdownMenuItem
              disabled={item.disabled}
              className={cn(item.danger && "text-destructive focus:text-destructive")}
              onSelect={() => {
                if (item.onClick) {
                  void item.onClick()
                } else {
                  onSelect(item.id)
                }
              }}
            >
              {item.icon && <item.icon className="mr-2 h-4 w-4" />}
              <span>{item.label}</span>
              {item.shortcut && <DropdownMenuShortcut>{item.shortcut}</DropdownMenuShortcut>}
            </DropdownMenuItem>
          )}
        </React.Fragment>
      ))}
      {!isLastGroup && <DropdownMenuSeparator />}
    </>
  )
}

/**
 * 桌面端菜单渲染器组件
 */
export function DesktopMenuRenderer({
  items,
  trigger,
  align,
  width,
  open,
  onOpenChange,
  onSelect,
  menuPosition,
  triggerElement,
  children,
  title,
  subtitle,
}: DesktopMenuRendererProps) {
  // 右键菜单使用隐藏的触发按钮定位
  const contextMenuTrigger = trigger === "context-menu" && (
    <button
      className="pointer-events-none fixed h-0 w-0 opacity-0"
      style={{ left: menuPosition.x, top: menuPosition.y }}
    />
  )

  return (
    <DropdownMenu open={open} onOpenChange={onOpenChange}>
      <DropdownMenuTrigger asChild>
        {trigger === "context-menu" ? (
          contextMenuTrigger
        ) : (
          triggerElement ?? children ?? <button className="pointer-events-none fixed h-0 w-0 opacity-0" />
        )}
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align={align}
        side="bottom"
        style={{ width: typeof width === "number" ? `${width}px` : width }}
      >
        {/* 用户信息头部 */}
        {title && (
          <div className="flex items-center justify-start gap-2 p-2">
            <div className="flex flex-col space-y-1 leading-none">
              <p className="font-medium">{title}</p>
              {subtitle && (
                <p className="w-[200px] truncate text-sm text-muted-foreground">
                  {subtitle}
                </p>
              )}
            </div>
          </div>
        )}
        {items.map((group, groupIndex) => (
          <MenuItemGroupRenderer
            key={groupIndex}
            group={group}
            onSelect={onSelect}
            isLastGroup={groupIndex === items.length - 1}
          />
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
