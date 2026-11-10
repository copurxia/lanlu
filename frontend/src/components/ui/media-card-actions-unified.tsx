/**
 * MediaCardActions组件 - 使用UnifiedMenu实现
 * @module media-card-actions
 */

"use client"

import { BookOpen, CheckCircle, Download, Edit, Heart, RotateCcw, Square, Trash2 } from 'lucide-react'
import { UnifiedMenu, type MenuItem } from '@/components/ui/unified-menu'
import type { BaseMediaCardType } from '@/components/ui/base-media-card.types'

type MediaCardActionsProps = {
  canDelete: boolean
  canEdit: boolean
  canToggleFavorite: boolean
  deleting: boolean
  favoriteLoading: boolean
  isFavorite: boolean
  isNew: boolean
  isNewStatusLoading: boolean
  menuOpen: boolean
  menuPosition: { x: number; y: number }
  onDelete: () => Promise<void>
  onDownload: () => void
  onOpenChange: (open: boolean) => void
  onOpenEdit: () => void
  onToggleFavorite: () => Promise<void>
  onToggleReadStatus: () => Promise<void>
  onUseMultiSelect: () => void
  onStartReading: () => void
  readStatusText: string
  readerTargetId: string
  selectable: boolean
  selectionMode: boolean
  t: (key: string) => string
  type: BaseMediaCardType
}

export function MediaCardActions({
  canDelete,
  canEdit,
  canToggleFavorite,
  deleting,
  favoriteLoading,
  isFavorite,
  isNew,
  isNewStatusLoading,
  menuOpen,
  menuPosition,
  onDelete,
  onDownload,
  onOpenChange,
  onOpenEdit,
  onToggleFavorite,
  onToggleReadStatus,
  onUseMultiSelect,
  onStartReading,
  readStatusText,
  readerTargetId,
  selectable,
  selectionMode,
  t,
  type,
}: MediaCardActionsProps) {
  const menuActionDisabled = deleting

  // 构建菜单项配置
  const menuItems: MenuItem[] = [
    // 多选模式
    ...(selectable && !selectionMode
      ? [
          {
            id: 'use-multi-select',
            label: t('home.useMultiSelect'),
            icon: Square,
            separator: true,
          },
        ]
      : []),
    // 开始阅读
    {
      id: 'start-reading',
      label: t('archive.startReading'),
      icon: BookOpen,
      disabled: !readerTargetId,
    },
    // Archive类型特有操作
    ...(type === 'archive'
      ? [
          {
            id: 'download',
            label: t('archive.download'),
            icon: Download,
            group: 'actions',
          },
          {
            id: 'toggle-read-status',
            label: readStatusText,
            icon: isNew ? CheckCircle : RotateCcw,
            disabled: menuActionDisabled || isNewStatusLoading,
            group: 'actions',
          },
        ]
      : []),
    // 收藏
    {
      id: 'toggle-favorite',
      label: favoriteLoading
        ? t('common.loading')
        : isFavorite
          ? t('common.unfavorite')
          : t('common.favorite'),
      icon: Heart,
      disabled: menuActionDisabled || favoriteLoading || !canToggleFavorite,
      group: 'actions',
      customRender: (item, close) => (
        <button
          key={item.id}
          className="relative flex w-full cursor-default select-none items-center rounded-sm px-2 py-1.5 text-sm outline-hidden transition-colors focus:bg-accent focus:text-accent-foreground data-disabled:pointer-events-none data-disabled:opacity-50"
          disabled={item.disabled}
          onClick={() => {
            void onToggleFavorite()
            close()
          }}
        >
          <Heart className={`mr-2 h-4 w-4 ${isFavorite ? 'fill-current text-red-500' : ''}`} />
          <span>{item.label}</span>
        </button>
      ),
    },
    // 编辑
    {
      id: 'edit',
      label: t('common.edit'),
      icon: Edit,
      disabled: menuActionDisabled || !canEdit,
      group: 'management',
    },
    // 删除
    {
      id: 'delete',
      label: deleting ? t('common.loading') : t('common.delete'),
      icon: Trash2,
      danger: true,
      disabled: menuActionDisabled || !canDelete,
      group: 'management',
    },
  ]

  // 处理菜单选择
  const handleSelect = (id: string) => {
    switch (id) {
      case 'use-multi-select':
        onUseMultiSelect()
        break
      case 'start-reading':
        onStartReading()
        break
      case 'download':
        onDownload()
        break
      case 'toggle-read-status':
        void onToggleReadStatus()
        break
      case 'edit':
        onOpenEdit()
        break
      case 'delete':
        void onDelete()
        break
    }
  }

  return (
    <UnifiedMenu
      items={menuItems}
      trigger="context-menu"
      align="start"
      width={208}
      open={menuOpen}
      onOpenChange={onOpenChange}
      onSelect={handleSelect}
      menuPosition={menuPosition}
    />
  )
}
