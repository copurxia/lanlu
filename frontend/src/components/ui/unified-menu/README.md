# UnifiedMenu 统一菜单组件

## 简介

UnifiedMenu 是一个通用的菜单组件，提供统一的 API 接口，支持桌面端下拉菜单和移动端抽屉式菜单的自动切换。该组件解决了现有项目中多种菜单实现方式不一致的问题，提供了一致的用户体验。

## 特性

- ✅ **响应式设计**：自动检测设备类型，桌面端显示下拉菜单，移动端显示抽屉式菜单
- ✅ **统一 API**：提供统一的配置接口，减少重复代码
- ✅ **多种触发方式**：支持点击、右键、悬停三种触发方式
- ✅ **菜单项分组**：支持按逻辑分组，自动插入分隔线
- ✅ **子菜单支持**：支持嵌套子菜单，桌面端悬停展开，移动端页面导航
- ✅ **自定义渲染**：支持自定义菜单项渲染
- ✅ **危险操作样式**：支持标记危险操作，显示红色警示样式
- ✅ **键盘导航**：完整的键盘导航支持，符合可访问性标准
- ✅ **动画效果**：流畅的打开/关闭动画，支持 reduced-motion 偏好

## 安装

组件已集成到项目中，无需额外安装。

## 基础使用

### 1. 基础点击菜单

```tsx
import { UnifiedMenu } from '@/components/ui/unified-menu'
import { Edit, Trash2 } from 'lucide-react'

function MyComponent() {
  const handleSelect = (id: string) => {
    console.log('Selected:', id)
  }

  return (
    <UnifiedMenu
      items={[
        { id: 'edit', label: 'Edit', icon: Edit },
        { id: 'delete', label: 'Delete', icon: Trash2, danger: true },
      ]}
      onSelect={handleSelect}
    >
      <Button>Open Menu</Button>
    </UnifiedMenu>
  )
}
```

### 2. 右键菜单

```tsx
import { UnifiedMenu } from '@/components/ui/unified-menu'

function MyComponent() {
  return (
    <UnifiedMenu
      trigger="context-menu"
      items={[
        { id: 'copy', label: 'Copy' },
        { id: 'paste', label: 'Paste' },
        { id: 'delete', label: 'Delete', danger: true },
      ]}
      onSelect={(id) => console.log('Selected:', id)}
    >
      <div>Right-click me</div>
    </UnifiedMenu>
  )
}
```

### 3. 菜单项分组

```tsx
import { UnifiedMenu } from '@/components/ui/unified-menu'

function MyComponent() {
  return (
    <UnifiedMenu
      items={[
        { id: 'edit', label: 'Edit', group: 'actions' },
        { id: 'duplicate', label: 'Duplicate', group: 'actions' },
        { id: 'delete', label: 'Delete', danger: true, group: 'danger' },
      ]}
      onSelect={(id) => console.log('Selected:', id)}
    >
      <Button>Open Menu</Button>
    </UnifiedMenu>
  )
}
```

### 4. 子菜单

```tsx
import { UnifiedMenu } from '@/components/ui/unified-menu'

function MyComponent() {
  return (
    <UnifiedMenu
      items={[
        {
          id: 'file',
          label: 'File',
          children: [
            { id: 'new', label: 'New' },
            { id: 'open', label: 'Open' },
            { id: 'save', label: 'Save' },
          ],
        },
        { id: 'edit', label: 'Edit' },
      ]}
      onSelect={(id) => console.log('Selected:', id)}
    >
      <Button>Open Menu</Button>
    </UnifiedMenu>
  )
}
```

### 5. 自定义渲染

```tsx
import { UnifiedMenu } from '@/components/ui/unified-menu'

function MyComponent() {
  return (
    <UnifiedMenu
      items={[
        {
          id: 'custom',
          label: 'Custom Item',
          customRender: (item, close) => (
            <div className="p-2 bg-blue-100" onClick={close}>
              {item.label} - Custom Rendered
            </div>
          ),
        },
      ]}
      onSelect={(id) => console.log('Selected:', id)}
    >
      <Button>Open Menu</Button>
    </UnifiedMenu>
  )
}
```

## API 文档

### UnifiedMenuProps

| 属性 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `items` | `MenuItem[]` | - | 菜单项列表（必需） |
| `trigger` | `'click' \| 'context-menu' \| 'hover'` | `'click'` | 触发方式 |
| `align` | `'start' \| 'center' \| 'end'` | `'start'` | 菜单对齐方式 |
| `title` | `string` | - | 菜单标题（移动端使用） |
| `onSelect` | `(id: string) => void` | - | 菜单选择回调 |
| `onOpenChange` | `(open: boolean) => void` | - | 菜单打开状态变化回调 |
| `triggerElement` | `React.ReactNode` | - | 自定义触发元素 |
| `width` | `string \| number` | `'auto'` | 菜单宽度（仅桌面端） |
| `forceMode` | `'desktop' \| 'mobile'` | - | 强制使用指定模式 |
| `children` | `React.ReactNode` | - | 子元素（作为触发源） |

### MenuItem

| 属性 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `id` | `string` | - | 菜单项唯一标识（必需） |
| `label` | `string` | - | 菜单项文本（必需） |
| `icon` | `LucideIcon` | - | 菜单项图标 |
| `shortcut` | `string` | - | 快捷键提示 |
| `disabled` | `boolean` | `false` | 是否禁用 |
| `danger` | `boolean` | `false` | 是否为危险操作 |
| `group` | `string` | - | 分组标识 |
| `separator` | `boolean` | `false` | 是否显示分隔线 |
| `children` | `MenuItem[]` | - | 子菜单项 |
| `customRender` | `(item, close) => ReactNode` | - | 自定义渲染函数 |
| `onClick` | `() => void \| Promise<void>` | - | 点击回调（覆盖 onSelect） |

## 迁移指南

### 从 MediaCardActions 迁移

原有的 `MediaCardActions` 组件使用 `DropdownMenu` 实现，现在可以使用新的 `media-card-actions-unified.tsx` 替换：

```tsx
// 修改前
import { MediaCardActions } from '@/components/ui/media-card-actions'

// 修改后
import { MediaCardActions } from '@/components/ui/media-card-actions-unified'
```

### 从 UserMenu 迁移

原有的 `UserMenu` 组件在桌面端使用 `DropdownMenu`，移动端使用 `Dialog`，现在可以使用新的 `UserMenuUnified.tsx` 替换：

```tsx
// 修改前
import { UserMenu } from '@/components/user/UserMenu'

// 修改后
import { UserMenu } from '@/components/user/UserMenuUnified'
```

## 最佳实践

1. **使用分组**：将相关的菜单项分组，提高可读性
2. **标记危险操作**：使用 `danger: true` 标记删除等危险操作
3. **提供图标**：为菜单项提供图标，提升用户体验
4. **禁用不可用项**：根据状态禁用不可用的菜单项
5. **使用自定义渲染**：对于特殊需求，使用 `customRender` 自定义渲染

## 可访问性

组件符合 WCAG 2.1 AA 级标准，支持：

- ✅ 完整的键盘导航（ArrowUp、ArrowDown、Enter、Escape）
- ✅ ARIA 属性（role="menu"、role="menuitem"）
- ✅ 屏幕阅读器支持
- ✅ 高对比度模式
- ✅ reduced-motion 偏好

## 浏览器兼容性

- Chrome (最新两个版本)
- Firefox (最新两个版本)
- Safari (最新两个版本)
- Edge (最新两个版本)

## 依赖

- @radix-ui/react-dropdown-menu
- @radix-ui/react-dialog
- lucide-react
- class-variance-authority
- tailwind-merge

## 文件结构

```
frontend/src/components/ui/unified-menu/
├── index.ts                          # 导出入口
├── unified-menu.tsx                  # 主组件
├── unified-menu.types.ts             # 类型定义
├── desktop-menu-renderer.tsx         # 桌面端渲染器
├── mobile-menu-renderer.tsx          # 移动端渲染器
├── hooks/
│   ├── use-media-query.ts            # 媒体查询Hook
│   └── use-long-press.ts             # 长按检测Hook
├── utils/
│   ├── group-menu-items.ts           # 菜单项分组工具
│   └── calculate-position.ts         # 位置计算工具
└── styles/
    └── menu-item-variants.ts         # CVA样式变体
```

## 示例项目

查看以下文件了解实际使用：

- `frontend/src/components/ui/media-card-actions-unified.tsx` - BaseMediaCard 右键菜单
- `frontend/src/components/user/UserMenuUnified.tsx` - UserMenu 头像菜单
