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
        className={cn(
          menuItemVariants({
            variant: item.danger ? "danger" : "default",
            disabled: item.disabled,
          }),
          "data-[state=open]:bg-accent"
        )}
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
                className={menuItemVariants({
                  variant: child.danger ? "danger" : "default",
                  disabled: child.disabled,
                })}
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
              className={menuItemVariants({
                variant: item.danger ? "danger" : "default",
                disabled: item.disabled,
              })}
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
  // 对于右键菜单，使用虚拟锚点定位
  if (trigger === "context-menu") {
    return (
      <DropdownMenu open={open} onOpenChange={onOpenChange}>
        <DropdownMenuContent
          align={align}
          side="bottom"
          style={{
            width: typeof width === "number" ? `${width}px` : width,
            position: 'fixed',
            left: menuPosition.x,
            top: menuPosition.y,
          }}
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

  // 对于点击触发的菜单，使用正常的触发器
  return (
    <DropdownMenu open={open} onOpenChange={onOpenChange}>
      <DropdownMenuTrigger asChild>
        {triggerElement ?? children ?? (
          <button className="sr-only" style={{ width: 0, height: 0, padding: 0, margin: 0, overflow: 'hidden', clip: 'rect(0, 0, 0, 0)', whiteSpace: 'nowrap', border: 0 }} />
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
