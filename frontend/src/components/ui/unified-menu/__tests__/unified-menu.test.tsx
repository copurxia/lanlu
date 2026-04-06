/**
 * UnifiedMenu 组件测试
 * @module unified-menu.test
 */

import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { UnifiedMenu } from '../unified-menu'
import type { MenuItem } from '../unified-menu.types'

// Mock useMediaQuery
vi.mock('../hooks/use-media-query', () => ({
  useMediaQuery: () => true, // 默认返回桌面端
}))

describe('UnifiedMenu', () => {
  const mockItems: MenuItem[] = [
    { id: 'edit', label: 'Edit' },
    { id: 'delete', label: 'Delete', danger: true },
  ]

  it('should render trigger element', () => {
    render(
      <UnifiedMenu items={mockItems}>
        <button>Open Menu</button>
      </UnifiedMenu>
    )

    expect(screen.getByText('Open Menu')).toBeInTheDocument()
  })

  it('should call onSelect when menu item is selected', async () => {
    const onSelect = vi.fn()

    render(
      <UnifiedMenu items={mockItems} onSelect={onSelect}>
        <button>Open Menu</button>
      </UnifiedMenu>
    )

    // 点击打开菜单
    const triggerButton = screen.getByText('Open Menu')
    fireEvent.click(triggerButton)

    // 等待菜单打开
    const editItem = await screen.findByText('Edit')
    expect(editItem).toBeInTheDocument()

    // 点击菜单项
    fireEvent.click(editItem)
    expect(onSelect).toHaveBeenCalledWith('edit')
  })

  it('should render menu items with icons', () => {
    const itemsWithIcons: MenuItem[] = [
      { id: 'edit', label: 'Edit', icon: () => <span data-testid="edit-icon">✏️</span> },
      { id: 'delete', label: 'Delete', icon: () => <span data-testid="delete-icon">🗑️</span> },
    ]

    render(
      <UnifiedMenu items={itemsWithIcons}>
        <button>Open Menu</button>
      </UnifiedMenu>
    )

    const triggerButton = screen.getByText('Open Menu')
    fireEvent.click(triggerButton)

    expect(screen.getByTestId('edit-icon')).toBeInTheDocument()
    expect(screen.getByTestId('delete-icon')).toBeInTheDocument()
  })

  it('should render disabled menu items', () => {
    const itemsWithDisabled: MenuItem[] = [
      { id: 'edit', label: 'Edit', disabled: true },
      { id: 'delete', label: 'Delete' },
    ]

    render(
      <UnifiedMenu items={itemsWithDisabled}>
        <button>Open Menu</button>
      </UnifiedMenu>
    )

    const triggerButton = screen.getByText('Open Menu')
    fireEvent.click(triggerButton)

    const editItem = screen.getByText('Edit')
    expect(editItem).toHaveAttribute('data-disabled', 'true')
  })

  it('should render danger menu items with correct styles', () => {
    render(
      <UnifiedMenu items={mockItems}>
        <button>Open Menu</button>
      </UnifiedMenu>
    )

    const triggerButton = screen.getByText('Open Menu')
    fireEvent.click(triggerButton)

    const deleteItem = screen.getByText('Delete')
    expect(deleteItem).toHaveClass('text-destructive')
  })

  it('should support custom trigger element', () => {
    render(
      <UnifiedMenu
        items={mockItems}
        triggerElement={<button>Custom Trigger</button>}
      />
    )

    expect(screen.getByText('Custom Trigger')).toBeInTheDocument()
  })

  it('should support menu title for mobile', () => {
    render(
      <UnifiedMenu items={mockItems} title="Menu Title">
        <button>Open Menu</button>
      </UnifiedMenu>
    )

    // 标题只在移动端显示，桌面端不显示
    expect(screen.queryByText('Menu Title')).not.toBeInTheDocument()
  })
})

describe('groupMenuItems', () => {
  it('should group items by group property', async () => {
    const { groupMenuItems } = await import('../utils/group-menu-items')

    const items: MenuItem[] = [
      { id: '1', label: 'Item 1', group: 'a' },
      { id: '2', label: 'Item 2', group: 'a' },
      { id: '3', label: 'Item 3', group: 'b' },
    ]

    const grouped = groupMenuItems(items)

    expect(grouped).toHaveLength(2)
    expect(grouped[0].id).toBe('a')
    expect(grouped[0].items).toHaveLength(2)
    expect(grouped[1].id).toBe('b')
    expect(grouped[1].items).toHaveLength(1)
  })

  it('should handle items without group', async () => {
    const { groupMenuItems } = await import('../utils/group-menu-items')

    const items: MenuItem[] = [
      { id: '1', label: 'Item 1' },
      { id: '2', label: 'Item 2' },
    ]

    const grouped = groupMenuItems(items)

    expect(grouped).toHaveLength(1)
    expect(grouped[0].id).toBeUndefined()
    expect(grouped[0].items).toHaveLength(2)
  })
})

describe('calculateMenuPosition', () => {
  it('should calculate position within viewport', async () => {
    const { calculateMenuPosition } = await import('../utils/calculate-position')

    // Mock window dimensions
    Object.defineProperty(window, 'innerWidth', { value: 1024, writable: true })
    Object.defineProperty(window, 'innerHeight', { value: 768, writable: true })

    const position = calculateMenuPosition(100, 100, 200, 300)

    expect(position.x).toBe(100)
    expect(position.y).toBe(100)
  })

  it('should adjust position when menu exceeds right boundary', async () => {
    const { calculateMenuPosition } = await import('../utils/calculate-position')

    Object.defineProperty(window, 'innerWidth', { value: 1024, writable: true })
    Object.defineProperty(window, 'innerHeight', { value: 768, writable: true })

    const position = calculateMenuPosition(900, 100, 200, 300)

    expect(position.x).toBe(1024 - 200 - 8)
  })

  it('should adjust position when menu exceeds bottom boundary', async () => {
    const { calculateMenuPosition } = await import('../utils/calculate-position')

    Object.defineProperty(window, 'innerWidth', { value: 1024, writable: true })
    Object.defineProperty(window, 'innerHeight', { value: 768, writable: true })

    const position = calculateMenuPosition(100, 600, 200, 300)

    expect(position.y).toBe(768 - 300 - 8)
  })
})
