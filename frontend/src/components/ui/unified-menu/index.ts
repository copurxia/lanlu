/**
 * 统一菜单组件导出入口
 * @module unified-menu
 */

export { UnifiedMenu } from "./unified-menu"
export type {
  UnifiedMenuProps,
  MenuItem,
  MenuItemGroup,
  TriggerMode,
  AlignMode,
  DesktopMenuRendererProps,
  MobileMenuRendererProps,
} from "./unified-menu.types"

export { useMediaQuery } from "./hooks/use-media-query"
export { useLongPress } from "./hooks/use-long-press"
export { groupMenuItems } from "./utils/group-menu-items"
export { calculateMenuPosition } from "./utils/calculate-position"
