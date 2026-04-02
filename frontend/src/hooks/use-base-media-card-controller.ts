import * as React from 'react'
import { useAuth } from '@/contexts/AuthContext'
import { useConfirmContext } from '@/contexts/ConfirmProvider'
import { useToast } from '@/hooks/use-toast'
import { ArchiveService } from '@/lib/services/archive-service'
import { TankoubonService } from '@/lib/services/tankoubon-service'
import { appEvents, AppEvents } from '@/lib/utils/events'
import { logger } from '@/lib/utils/logger'
import type { BaseMediaCardType } from '@/components/ui/base-media-card.types'

const DEFAULT_COVER_ASPECT_RATIO = 3 / 4
const coverAspectRatioCache = new Map<string, number>()

function normalizeCoverAspectRatio(width: number, height: number): number {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return DEFAULT_COVER_ASPECT_RATIO
  }
  return width / height
}

function getCachedCoverAspectRatio(src: string): number {
  if (!src) return DEFAULT_COVER_ASPECT_RATIO
  return coverAspectRatioCache.get(src) ?? DEFAULT_COVER_ASPECT_RATIO
}

function hasCachedCoverAspectRatio(src: string): boolean {
  return Boolean(src) && coverAspectRatioCache.has(src)
}

type UseBaseMediaCardControllerOptions = {
  hasImage: boolean
  id: string
  imageSrc: string
  isfavorite?: boolean
  isnew?: boolean
  onCoverAspectRatioChange?: (aspectRatio: number) => void
  onFavoriteToggle?: (id: string, isFavorite: boolean) => Promise<boolean>
  onRequestEnterSelection?: () => void
  onToggleSelect?: (selected: boolean) => void
  selectable: boolean
  selected: boolean
  selectionMode: boolean
  summary?: string
  t: (key: string) => string
  tags?: string
  title: string
  trackFavorite: () => void
  type: BaseMediaCardType
}

export function useBaseMediaCardController({
  hasImage,
  id,
  imageSrc,
  isfavorite = false,
  isnew = false,
  onCoverAspectRatioChange,
  onFavoriteToggle,
  onRequestEnterSelection,
  onToggleSelect,
  selectable,
  selected,
  selectionMode,
  summary,
  t,
  tags,
  title,
  trackFavorite,
  type,
}: UseBaseMediaCardControllerOptions) {
  const { isAuthenticated, user } = useAuth()
  const { confirm } = useConfirmContext()
  const { error: showError } = useToast()

  const [isFavorite, setIsFavorite] = React.useState(isfavorite)
  const [isNew, setIsNew] = React.useState(isnew)
  const [favoriteLoading, setFavoriteLoading] = React.useState(false)
  const [isNewStatusLoading, setIsNewStatusLoading] = React.useState(false)
  const [deleting, setDeleting] = React.useState(false)
  const [imageError, setImageError] = React.useState(false)
  const [coverNaturalAspectRatio, setCoverNaturalAspectRatio] = React.useState(() => getCachedCoverAspectRatio(imageSrc))
  const [displayTitle, setDisplayTitle] = React.useState(title)
  const [displaySummary, setDisplaySummary] = React.useState(summary || '')
  const [displayTags, setDisplayTags] = React.useState(tags || '')
  const [editOpen, setEditOpen] = React.useState(false)
  const [menuOpen, setMenuOpen] = React.useState(false)
  const [menuPosition, setMenuPosition] = React.useState({ x: 0, y: 0 })
  const hasMeasuredCoverAspectRatioRef = React.useRef(false)

  const isAdmin = user?.isAdmin === true
  const canEdit = isAuthenticated
  const canDelete = type === 'archive' ? isAdmin : isAuthenticated

  React.useEffect(() => {
    setDisplayTitle(title)
  }, [title])

  React.useEffect(() => {
    setDisplaySummary(summary || '')
  }, [summary])

  React.useEffect(() => {
    setDisplayTags(tags || '')
  }, [tags])

  React.useEffect(() => {
    setIsFavorite(isfavorite)
  }, [isfavorite])

  React.useEffect(() => {
    setIsNew(isnew)
  }, [isnew])

  React.useEffect(() => {
    setImageError(false)
    hasMeasuredCoverAspectRatioRef.current = false
    setCoverNaturalAspectRatio(getCachedCoverAspectRatio(imageSrc))
  }, [imageSrc])

  React.useEffect(() => {
    if (!onCoverAspectRatioChange || !hasImage || imageError) return
    if (!hasMeasuredCoverAspectRatioRef.current && !hasCachedCoverAspectRatio(imageSrc)) return
    onCoverAspectRatioChange(coverNaturalAspectRatio)
  }, [coverNaturalAspectRatio, hasImage, imageError, imageSrc, onCoverAspectRatioChange])

  const emitRefresh = React.useCallback(() => {
    appEvents.emit(AppEvents.ARCHIVES_REFRESH)
  }, [])

  const handleImageLoad = React.useCallback((event: React.SyntheticEvent<HTMLImageElement>) => {
    const element = event.currentTarget
    const nextAspectRatio = normalizeCoverAspectRatio(element.naturalWidth || element.width, element.naturalHeight || element.height)
    if (imageSrc) {
      coverAspectRatioCache.set(imageSrc, nextAspectRatio)
    }
    hasMeasuredCoverAspectRatioRef.current = true

    setCoverNaturalAspectRatio((current) => {
      if (Math.abs(current - nextAspectRatio) < 0.001) return current
      return nextAspectRatio
    })
  }, [imageSrc])

  const handleImageError = React.useCallback(() => {
    setImageError(true)
    setCoverNaturalAspectRatio(DEFAULT_COVER_ASPECT_RATIO)
  }, [])

  const toggleSelected = React.useCallback((nextSelected?: boolean) => {
    if (!selectable || !onToggleSelect) return
    const value = typeof nextSelected === 'boolean' ? nextSelected : !selected
    if (value && !selectionMode) onRequestEnterSelection?.()
    onToggleSelect(value)
  }, [onRequestEnterSelection, onToggleSelect, selectable, selected, selectionMode])

  const toggleFavorite = React.useCallback(async () => {
    if (favoriteLoading || !onFavoriteToggle) return
    setFavoriteLoading(true)
    try {
      const success = await onFavoriteToggle(id, isFavorite)
      if (!success) return

      const nextFavorite = !isFavorite
      setIsFavorite(nextFavorite)
      if (nextFavorite) {
        trackFavorite()
      }
    } catch (error) {
      logger.operationFailed('toggle favorite', error, { id, type })
    } finally {
      setFavoriteLoading(false)
    }
  }, [favoriteLoading, id, isFavorite, onFavoriteToggle, trackFavorite, type])

  const handleContextMenu = React.useCallback((event: React.MouseEvent) => {
    event.preventDefault()
    event.stopPropagation()
    if (selectionMode) return
    setMenuPosition({ x: event.clientX, y: event.clientY })
    setMenuOpen(true)
  }, [selectionMode])

  const handleDownload = React.useCallback(() => {
    if (type !== 'archive') return
    window.open(ArchiveService.getDownloadUrl(id), '_blank')
  }, [id, type])

  const handleToggleReadStatus = React.useCallback(async () => {
    if (type !== 'archive' || isNewStatusLoading) return
    setIsNewStatusLoading(true)
    try {
      if (isNew) {
        await ArchiveService.clearIsNew(id)
      } else {
        await ArchiveService.setIsNew(id)
      }
      setIsNew(!isNew)
      emitRefresh()
    } catch (error) {
      logger.operationFailed('toggle archive read status', error, { id })
      showError(isNew ? t('archive.markAsReadFailed') : t('archive.markAsNewFailed'))
    } finally {
      setIsNewStatusLoading(false)
    }
  }, [emitRefresh, id, isNew, isNewStatusLoading, showError, t, type])

  const handleOpenEdit = React.useCallback(() => {
    if (!canEdit) {
      showError(t('library.loginRequired'))
      return
    }
    setEditOpen(true)
  }, [canEdit, showError, t])

  const handleDelete = React.useCallback(async () => {
    if (!canDelete) {
      showError(type === 'archive' ? t('common.accessDenied') : t('library.loginRequired'))
      return
    }
    if (deleting) return

    const confirmed = await confirm({
      title: type === 'archive' ? t('common.delete') : t('tankoubon.deleteConfirmTitle'),
      description:
        type === 'archive'
          ? `${t('common.delete')} ${t('archive.archiveLabel')}: "${displayTitle}"`
          : t('tankoubon.deleteConfirmMessage'),
      confirmText: t('common.delete'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    })
    if (!confirmed) return

    setDeleting(true)
    try {
      if (type === 'archive') {
        await ArchiveService.deleteArchive(id)
      } else {
        await TankoubonService.deleteTankoubon(id)
      }
      emitRefresh()
    } catch (error) {
      logger.operationFailed('delete from card menu', error, { id, type })
      showError(t('common.error'))
    } finally {
      setDeleting(false)
    }
  }, [canDelete, confirm, deleting, displayTitle, emitRefresh, id, showError, t, type])

  const handleEditSaved = React.useCallback((next: { summary: string; tags: string; title: string }) => {
    setDisplayTitle(next.title)
    setDisplaySummary(next.summary)
    setDisplayTags(next.tags)
  }, [])

  return {
    canDelete,
    canEdit,
    coverNaturalAspectRatio,
    deleting,
    displaySummary,
    displayTags,
    displayTitle,
    editOpen,
    favoriteLoading,
    handleContextMenu,
    handleDelete,
    handleDownload,
    handleEditSaved,
    handleImageError,
    handleImageLoad,
    handleOpenEdit,
    handleToggleReadStatus,
    imageError,
    isFavorite,
    isNew,
    isNewStatusLoading,
    menuOpen,
    menuPosition,
    readStatusText: isNewStatusLoading ? t('common.loading') : isNew ? t('archive.markAsRead') : t('archive.markAsNew'),
    setEditOpen,
    setMenuOpen,
    toggleFavorite,
    toggleSelected,
  }
}
