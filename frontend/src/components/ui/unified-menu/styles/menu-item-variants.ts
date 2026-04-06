/**
 * 菜单项样式变体定义
 * @module menu-item-variants
 */

import { cva, type VariantProps } from "class-variance-authority"

/**
 * 桌面端菜单项样式变体
 */
export const menuItemVariants = cva(
  "relative flex cursor-default select-none items-center rounded-sm px-2 py-1.5 text-sm outline-hidden transition-colors",
  {
    variants: {
      variant: {
        default: "focus:bg-accent focus:text-accent-foreground",
        danger: "text-destructive focus:text-destructive focus:bg-destructive/10",
      },
      disabled: {
        true: "pointer-events-none opacity-50",
        false: "",
      },
    },
    defaultVariants: {
      variant: "default",
      disabled: false,
    },
  }
)

/**
 * 移动端菜单项样式变体
 */
export const mobileMenuItemVariants = cva(
  "w-full justify-start h-auto py-3 px-4 rounded-md text-sm font-medium transition-colors",
  {
    variants: {
      variant: {
        default: "text-foreground hover:bg-accent hover:text-accent-foreground",
        danger: "text-destructive hover:text-destructive hover:bg-destructive/10",
      },
      disabled: {
        true: "pointer-events-none opacity-50",
        false: "",
      },
    },
    defaultVariants: {
      variant: "default",
      disabled: false,
    },
  }
)

/**
 * 桌面端菜单项样式变体类型
 */
export type MenuItemVariants = VariantProps<typeof menuItemVariants>

/**
 * 移动端菜单项样式变体类型
 */
export type MobileMenuItemVariants = VariantProps<typeof mobileMenuItemVariants>
