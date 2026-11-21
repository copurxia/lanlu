/**
 * 统一菜单组件类型定义
 * @module unified-menu.types
 */

import type { LucideIcon } from "lucide-react"

/**
 * 触发方式类型
 * - 'click': 点击触发（默认）
 * - 'context-menu': 右键触发
 * - 'hover': 悬停触发（仅桌面端）
 */
export type TriggerMode = "click" | "context-menu" | "hover"

/**
 * 对齐方式类型
 * - 'start': 左对齐（默认）
 * - 'center': 居中对齐
 * - 'end': 右对齐
 */
export type AlignMode = "start" | "center" | "end"

/**
 * 菜单项配置接口
 */
export interface MenuItem {
  /**
   * 菜单项唯一标识
   */
  id: string

  /**
   * 菜单项文本
   */
  label: string

  /**
   * 菜单项图标（Lucide图标组件）
   */
  icon?: LucideIcon

  /**
   * 快捷键提示
   */
  shortcut?: string

  /**
   * 是否禁用
   */
  disabled?: boolean

  /**
   * 是否为危险操作（红色样式）
   */
  danger?: boolean

  /**
   * 分组标识（相同group的项会被分到一组）
   */
  group?: string

  /**
   * 是否显示分隔线（在该项前插入分隔线）
   */
  separator?: boolean

  /**
   * 子菜单项（嵌套菜单）
   */
  children?: MenuItem[]

  /**
   * 自定义渲染函数
   */
  customRender?: (item: MenuItem, close: () => void) => React.ReactNode

  /**
   * 点击回调（覆盖onSelect）
   */
  onClick?: () => void | Promise<void>
}

/**
 * 菜单项分组结构
 */
export interface MenuItemGroup {
  /**
   * 分组标识
   */
  id?: string

  /**
   * 分组内的菜单项
   */
  items: MenuItem[]
}

/**
 * 统一菜单组件属性接口
 */
export interface UnifiedMenuProps {
  /**
   * 菜单项列表
   */
  items: MenuItem[]

  /**
   * 触发方式
   * @default 'click'
   */
  trigger?: TriggerMode

  /**
   * 菜单对齐方式
   * @default 'start'
   */
  align?: AlignMode

  /**
   * 菜单标题（移动端抽屉菜单使用）
   */
  title?: string

  /**
   * 菜单副标题（如"已登录"）
   */
  subtitle?: string

  /**
   * 菜单选择回调
   */
  onSelect?: (id: string) => void

  /**
   * 菜单打开状态变化回调
   */
  onOpenChange?: (open: boolean) => void

  /**
   * 自定义触发元素
   */
  triggerElement?: React.ReactNode

  /**
   * 菜单宽度（仅桌面端）
   * @default 'auto'
   */
  width?: string | number

  /**
   * 禁用响应式（强制使用指定模式）
   */
  forceMode?: "desktop" | "mobile"

  /**
   * 子元素（作为触发源）
   */
  children?: React.ReactNode

  /**
   * 菜单打开状态（受控模式）
   */
  open?: boolean

  /**
   * 菜单位置（右键菜单使用）
   */
  menuPosition?: { x: number; y: number }
}

/**
 * 桌面端菜单渲染器属性接口
 */
export interface DesktopMenuRendererProps {
  items: MenuItemGroup[]
  trigger: TriggerMode
  align: AlignMode
  width: string | number
  open: boolean
  onOpenChange: (open: boolean) => void
  onSelect: (id: string) => void
  menuPosition: { x: number; y: number }
  triggerElement?: React.ReactNode
  children?: React.ReactNode
  title?: string
  subtitle?: string
}

/**
 * 移动端菜单渲染器属性接口
 */
export interface MobileMenuRendererProps {
  items: MenuItemGroup[]
  title?: string
  subtitle?: string
  open: boolean
  onOpenChange: (open: boolean) => void
  onSelect: (id: string) => void
  triggerElement?: React.ReactNode
  children?: React.ReactNode
}
