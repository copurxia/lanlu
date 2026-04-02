"use client"

import { BookOpen, CheckCircle, Download, Edit, Heart, RotateCcw, Square, Trash2 } from 'lucide-react'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
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

  return (
    <DropdownMenu open={menuOpen} onOpenChange={onOpenChange}>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          aria-hidden
          className="pointer-events-none fixed h-0 w-0 opacity-0"
          style={{ left: menuPosition.x, top: menuPosition.y }}
        />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" side="bottom" className="w-52">
        {selectable && !selectionMode && (
          <>
            <DropdownMenuItem onSelect={onUseMultiSelect}>
              <Square className="mr-2 h-4 w-4" />
              {t('home.useMultiSelect')}
            </DropdownMenuItem>
            <DropdownMenuSeparator />
          </>
        )}
        <DropdownMenuItem disabled={!readerTargetId} onSelect={onStartReading}>
          <BookOpen className="mr-2 h-4 w-4" />
          {t('archive.startReading')}
        </DropdownMenuItem>

        {type === 'archive' && (
          <>
            <DropdownMenuItem onSelect={onDownload}>
              <Download className="mr-2 h-4 w-4" />
              {t('archive.download')}
            </DropdownMenuItem>
            <DropdownMenuItem disabled={menuActionDisabled || isNewStatusLoading} onSelect={() => void onToggleReadStatus()}>
              {isNew ? <CheckCircle className="mr-2 h-4 w-4" /> : <RotateCcw className="mr-2 h-4 w-4" />}
              {readStatusText}
            </DropdownMenuItem>
          </>
        )}

        <DropdownMenuItem
          disabled={menuActionDisabled || favoriteLoading || !canToggleFavorite}
          onSelect={() => {
            void onToggleFavorite()
          }}
        >
          <Heart className={`mr-2 h-4 w-4 ${isFavorite ? 'fill-current text-red-500' : ''}`} />
          {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
        </DropdownMenuItem>

        <DropdownMenuSeparator />

        <DropdownMenuItem disabled={menuActionDisabled || !canEdit} onSelect={onOpenEdit}>
          <Edit className="mr-2 h-4 w-4" />
          {t('common.edit')}
        </DropdownMenuItem>
        <DropdownMenuItem
          disabled={menuActionDisabled || !canDelete}
          className="text-destructive focus:text-destructive"
          onSelect={() => {
            void onDelete()
          }}
        >
          <Trash2 className="mr-2 h-4 w-4" />
          {deleting ? t('common.loading') : t('common.delete')}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
