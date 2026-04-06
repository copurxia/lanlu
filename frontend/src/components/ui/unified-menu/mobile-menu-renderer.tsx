/**
 * 移动端菜单渲染器
 * @module mobile-menu-renderer
 */

"use client"

import * as React from "react"
import { Button } from "@/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { cn } from "@/lib/utils/utils"
import { ChevronLeft } from "lucide-react"
import type { MobileMenuRendererProps, MenuItem, MenuItemGroup } from "./unified-menu.types"
import { mobileMenuItemVariants } from "./styles/menu-item-variants"

/**
 * 移动端子菜单渲染器
 */
function MobileSubMenuItemRenderer({
  item,
  onSelect,
  onBack,
}: {
  item: MenuItem
  onSelect: (id: string) => void
  onBack: () => void
}) {
  const [showSubMenu, setShowSubMenu] = React.useState(false)

  if (!item.children) return null

  return (
    <>
      <Button
        variant="ghost"
        disabled={item.disabled}
        className={cn(
          "w-full justify-start h-auto py-3 px-2",
          item.danger && "text-destructive hover:text-destructive"
        )}
        onClick={() => setShowSubMenu(true)}
      >
        {item.icon && <item.icon className="mr-2 h-4 w-4" />}
        <span className="flex-1 text-left">{item.label}</span>
        <ChevronLeft className="ml-auto h-4 w-4 rotate-180" />
      </Button>

      {showSubMenu && (
        <div className="fixed inset-0 z-[60] bg-background">
          <div className="flex h-full flex-col">
            <div className="flex items-center border-b px-4 py-3">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowSubMenu(false)}
                className="mr-2"
              >
                <ChevronLeft className="h-4 w-4" />
              </Button>
              <span className="text-lg font-semibold">{item.label}</span>
            </div>
            <div className="flex-1 overflow-y-auto p-2">
              {item.children.map((child) => (
                <React.Fragment key={child.id}>
                  {child.separator && <div className="my-2 h-px bg-border" />}
                  {child.children ? (
                    <MobileSubMenuItemRenderer
                      item={child}
                      onSelect={onSelect}
                      onBack={() => setShowSubMenu(false)}
                    />
                  ) : (
                    <Button
                      variant="ghost"
                      disabled={child.disabled}
                      className={cn(
                        "w-full justify-start h-auto py-3 px-2",
                        child.danger && "text-destructive hover:text-destructive"
                      )}
                      onClick={() => {
                        if (child.onClick) {
                          void child.onClick()
                        } else {
                          onSelect(child.id)
                        }
                        setShowSubMenu(false)
                        onBack()
                      }}
                    >
                      {child.icon && <child.icon className="mr-2 h-4 w-4" />}
                      <span>{child.label}</span>
                    </Button>
                  )}
                </React.Fragment>
              ))}
            </div>
          </div>
        </div>
      )}
    </>
  )
}

/**
 * 移动端菜单组渲染器
 */
function MobileMenuItemGroupRenderer({
  group,
  onSelect,
  isLastGroup,
  onClose,
}: {
  group: MenuItemGroup
  onSelect: (id: string) => void
  isLastGroup: boolean
  onClose: () => void
}) {
  return (
    <>
      {group.items.map((item) => (
        <React.Fragment key={item.id}>
          {item.separator && <div className="my-2 h-px bg-border" />}
          {item.customRender ? (
            item.customRender(item, () => {
              onSelect(item.id)
              onClose()
            })
          ) : item.children ? (
            <MobileSubMenuItemRenderer
              item={item}
              onSelect={onSelect}
              onBack={onClose}
            />
          ) : (
            <Button
              variant="ghost"
              disabled={item.disabled}
              className={cn(
                "w-full justify-start h-auto py-3 px-2",
                item.danger && "text-destructive hover:text-destructive"
              )}
              onClick={() => {
                if (item.onClick) {
                  void item.onClick()
                } else {
                  onSelect(item.id)
                }
                onClose()
              }}
            >
              {item.icon && <item.icon className="mr-2 h-4 w-4" />}
              <span>{item.label}</span>
            </Button>
          )}
        </React.Fragment>
      ))}
      {!isLastGroup && <div className="my-2 h-px bg-border" />}
    </>
  )
}

/**
 * 移动端菜单渲染器组件
 */
export function MobileMenuRenderer({
  items,
  title,
  subtitle,
  open,
  onOpenChange,
  onSelect,
  triggerElement,
  children,
}: MobileMenuRendererProps) {
  const handleClose = () => {
    onOpenChange(false)
  }

  // 克隆triggerElement并添加onClick事件
  const triggerWithClick = React.useMemo(() => {
    if (!triggerElement && !children) return null
    
    const element = triggerElement ?? children
    if (!element) return null
    
    // 如果是React元素，克隆并添加onClick
    if (React.isValidElement(element)) {
      return React.cloneElement(element as React.ReactElement<any>, {
        onClick: (e: React.MouseEvent) => {
          // 调用原有的onClick（如果存在）
          const originalOnClick = (element as React.ReactElement<any>).props?.onClick
          if (originalOnClick) {
            originalOnClick(e)
          }
          // 打开菜单
          onOpenChange(true)
        },
      })
    }
    
    return element
  }, [triggerElement, children, onOpenChange])

  return (
    <>
      {triggerWithClick}
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent side="bottom" className="h-auto max-h-[80vh]">
          {title && (
            <SheetHeader className="pb-2">
              <SheetTitle className="text-center">{title}</SheetTitle>
              {subtitle && (
                <p className="text-center text-sm text-muted-foreground">{subtitle}</p>
              )}
            </SheetHeader>
          )}
          <div className="flex flex-col gap-1 overflow-y-auto">
            {items.map((group, groupIndex) => (
              <MobileMenuItemGroupRenderer
                key={groupIndex}
                group={group}
                onSelect={onSelect}
                isLastGroup={groupIndex === items.length - 1}
                onClose={handleClose}
              />
            ))}
          </div>
        </SheetContent>
      </Sheet>
    </>
  )
}
