"use client"

import * as React from "react"
import { useRouter } from 'next/navigation'
import Image from 'next/image'
import Link from 'next/link'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { BookOpen, CheckCircle, Download, Edit, Eye, Heart, RotateCcw, Trash2 } from 'lucide-react'
import { ArchiveService } from '@/lib/services/archive-service'
import { TankoubonService } from '@/lib/services/tankoubon-service'
import { TaskPoolService } from '@/lib/services/taskpool-service'
import { PluginService } from '@/lib/services/plugin-service'
import { ArchiveMetadataEditDialog, type RpcSelectRequest } from '@/components/archive/ArchiveMetadataEditDialog'
import { useLanguage } from '@/contexts/LanguageContext'
import { useAuth } from '@/contexts/AuthContext'
import { useToast } from '@/hooks/use-toast'
import { useConfirmContext } from '@/contexts/ConfirmProvider'
import { appEvents, AppEvents } from '@/lib/utils/events'
import { logger } from '@/lib/utils/logger'
import { stripNamespace, parseTags } from '@/lib/utils/tag-utils'
import type { Plugin } from '@/lib/services/plugin-service'

export interface BaseMediaCardProps {
  // 基础信息
  id: string
  title: string
  thumbnailId: string
  thumbnailAssetId?: number
  thumbnailUrl?: string
  tags?: string
  summary?: string
  pagecount: number
  progress?: number
  isnew?: boolean
  isfavorite?: boolean

  // 类型区分
  type: 'archive' | 'tankoubon'

  // 可选配置
  index?: number
  badge?: React.ReactNode
  extraBadge?: React.ReactNode
  detailsLabel?: string
  pagesLabel?: string
  priority?: boolean  // 优先加载图片（用于 LCP 优化）
  hideMetaOnMobile?: boolean
  disableContentVisibility?: boolean

  // 收藏回调
  onFavoriteToggle?: (id: string, isFavorite: boolean) => Promise<boolean>
}

function toTagList(raw?: string): string[] {
  return String(raw || '')
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean)
}

function parseRpcSelectRequest(message: string): RpcSelectRequest | null {
  const prefix = '[RPC_SELECT]'
  if (!message?.startsWith(prefix)) return null
  try {
    const parsed = JSON.parse(message.slice(prefix.length)) as RpcSelectRequest
    if (!parsed?.request_id || !Array.isArray(parsed?.options) || parsed.options.length === 0) {
      return null
    }
    return parsed
  } catch {
    return null
  }
}

export function BaseMediaCard({
  id,
  title,
  thumbnailId,
  thumbnailAssetId,
  thumbnailUrl,
  tags,
  summary,
  pagecount,
  progress = 0,
  isnew = false,
  isfavorite = false,
  type,
  index = 0,
  badge,
  extraBadge,
  detailsLabel,
  pagesLabel,
  priority = false,
  hideMetaOnMobile = false,
  disableContentVisibility = false,
  onFavoriteToggle,
}: BaseMediaCardProps) {
  const router = useRouter()
  const { t } = useLanguage()
  const { isAuthenticated, user } = useAuth()
  const { error: showError } = useToast()
  const { confirm } = useConfirmContext()

  const [isFavorite, setIsFavorite] = React.useState(isfavorite)
  const [isNew, setIsNew] = React.useState(isnew)
  const [favoriteLoading, setFavoriteLoading] = React.useState(false)
  const [isNewStatusLoading, setIsNewStatusLoading] = React.useState(false)
  const [deleting, setDeleting] = React.useState(false)
  const [imageError, setImageError] = React.useState(false)
  const [displayTitle, setDisplayTitle] = React.useState(title)
  const [displaySummary, setDisplaySummary] = React.useState(summary || '')
  const [displayTags, setDisplayTags] = React.useState(tags || '')
  const [editOpen, setEditOpen] = React.useState(false)
  const [editSaving, setEditSaving] = React.useState(false)
  const [editTitle, setEditTitle] = React.useState(title)
  const [editSummary, setEditSummary] = React.useState(summary || '')
  const [editTags, setEditTags] = React.useState<string[]>(toTagList(tags))
  const [metadataPlugins, setMetadataPlugins] = React.useState<Plugin[]>([])
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = React.useState<string>('')
  const [metadataPluginParam, setMetadataPluginParam] = React.useState<string>('')
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = React.useState(false)
  const [metadataPluginProgress, setMetadataPluginProgress] = React.useState<number | null>(null)
  const [metadataPluginMessage, setMetadataPluginMessage] = React.useState('')
  const [metadataArchivePatches, setMetadataArchivePatches] = React.useState<Array<{
    archive_id?: string
    volume_no?: number
    title?: string
    summary?: string
    tags?: string
    updated_at?: string
    cover?: string
  }>>([])
  const [rpcSelectTaskId, setRpcSelectTaskId] = React.useState<number | null>(null)
  const [rpcSelectRequest, setRpcSelectRequest] = React.useState<RpcSelectRequest | null>(null)
  const [rpcSelectSelectedIndex, setRpcSelectSelectedIndex] = React.useState<number | null>(null)
  const [rpcSelectRemainingSeconds, setRpcSelectRemainingSeconds] = React.useState<number | null>(null)
  const resolvedRpcSelectRequestIdsRef = React.useRef<Set<string>>(new Set())
  const [menuOpen, setMenuOpen] = React.useState(false)
  const [menuPosition, setMenuPosition] = React.useState({ x: 0, y: 0 })

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
    if (!editOpen || !isAuthenticated) return
    let cancelled = false

    ;(async () => {
      try {
        const metas = await PluginService.getMetadataPlugins()
        if (cancelled) return
        setMetadataPlugins(metas)
        if (!selectedMetadataPlugin && metas.length > 0) {
          setSelectedMetadataPlugin(metas[0].namespace)
        }
      } catch (error) {
        logger.apiError('load metadata plugins (card)', error)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [editOpen, isAuthenticated, selectedMetadataPlugin, type])

  React.useEffect(() => {
    if (!rpcSelectRequest || rpcSelectRemainingSeconds == null) return
    if (rpcSelectRemainingSeconds <= 0) {
      setRpcSelectRequest(null)
      setRpcSelectTaskId(null)
      setRpcSelectSelectedIndex(null)
      setRpcSelectRemainingSeconds(null)
      return
    }

    const timer = window.setTimeout(() => {
      setRpcSelectRemainingSeconds((current) => {
        if (current == null) return null
        return Math.max(0, current - 1)
      })
    }, 1000)

    return () => window.clearTimeout(timer)
  }, [rpcSelectRemainingSeconds, rpcSelectRequest])

  const allTags = React.useMemo(() => parseTags(displayTags), [displayTags])
  const displayAllTags = React.useMemo(() => allTags.map(stripNamespace), [allTags])
  const maxHoverTags = React.useMemo(() => (displaySummary ? 5 : 8), [displaySummary])
  const hoverTags = React.useMemo(() => {
    return allTags
      .filter((tag) => {
        const stripped = stripNamespace(tag).toLowerCase()
        return !stripped.includes('source') && !tag.toLowerCase().includes('source')
      })
      .slice(0, maxHoverTags)
  }, [allTags, maxHoverTags])

  const hoverTitleParts = React.useMemo(() => [
    displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
    displaySummary ? `${t('archive.summary')}: ${displaySummary}` : ''
  ].filter(Boolean), [displayAllTags, displaySummary, t])

  // Avoid promoting hundreds of cards into animation/compositor work during scroll.
  const shouldEntranceAnimate = index < 24
  const animationDelay = shouldEntranceAnimate ? Math.min(index * 50, 500) : 0
  const detailPath = type === 'archive' ? `/archive?id=${id}` : `/tankoubon?id=${id}`
  const readerTargetId = type === 'archive' ? id : thumbnailId
  const readerPath = readerTargetId ? `/reader?id=${readerTargetId}` : detailPath
  const imageSrc = thumbnailUrl && thumbnailUrl.trim().length > 0
    ? thumbnailUrl
    : ArchiveService.getAssetUrl(thumbnailAssetId)
  const hasImage = imageSrc.trim().length > 0
  const progressPercent = pagecount > 0 ? Math.round((progress / pagecount) * 100) : 0

  const emitRefresh = React.useCallback(() => {
    appEvents.emit(AppEvents.ARCHIVES_REFRESH)
  }, [])

  const navigateToReader = React.useCallback(() => {
    router.push(readerPath)
  }, [readerPath, router])

  const toggleFavorite = React.useCallback(async () => {
    if (favoriteLoading || !onFavoriteToggle) return
    setFavoriteLoading(true)
    try {
      const success = await onFavoriteToggle(id, isFavorite)
      if (success) {
        setIsFavorite(!isFavorite)
        emitRefresh()
      }
    } catch (error) {
      logger.operationFailed('toggle favorite', error, { id, type })
    } finally {
      setFavoriteLoading(false)
    }
  }, [emitRefresh, favoriteLoading, id, isFavorite, onFavoriteToggle, type])

  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation()
    await toggleFavorite()
  }

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setMenuPosition({ x: e.clientX, y: e.clientY })
    setMenuOpen(true)
  }

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
    setEditTitle(displayTitle)
    setEditSummary(displaySummary)
    setEditTags(toTagList(displayTags))
    setMetadataArchivePatches([])
    setMetadataPluginProgress(null)
    setMetadataPluginMessage('')
    resolvedRpcSelectRequestIdsRef.current.clear()
    setRpcSelectRequest(null)
    setRpcSelectTaskId(null)
    setRpcSelectSelectedIndex(null)
    setRpcSelectRemainingSeconds(null)
    setEditOpen(true)
  }, [canEdit, displaySummary, displayTags, displayTitle, showError, t])

  const submitRpcSelect = React.useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest || rpcSelectSelectedIndex == null) return
    const requestId = rpcSelectRequest.request_id
    const ok = await TaskPoolService.respondRpcSelect(rpcSelectTaskId, requestId, rpcSelectSelectedIndex)
    resolvedRpcSelectRequestIdsRef.current.add(requestId)
    if (!ok) {
      showError('提交选择失败，可能请求已过期')
      setRpcSelectRequest(null)
      setRpcSelectTaskId(null)
      setRpcSelectSelectedIndex(null)
      setRpcSelectRemainingSeconds(null)
      return
    }
    setRpcSelectRequest(null)
    setRpcSelectTaskId(null)
    setRpcSelectSelectedIndex(null)
    setRpcSelectRemainingSeconds(null)
  }, [rpcSelectRequest, rpcSelectSelectedIndex, rpcSelectTaskId, showError])

  const abortRpcSelect = React.useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest) return
    const requestId = rpcSelectRequest.request_id
    const ok = await TaskPoolService.abortRpcSelect(rpcSelectTaskId, requestId)
    resolvedRpcSelectRequestIdsRef.current.add(requestId)
    if (!ok) {
      showError('放弃选择失败，可能请求已过期')
      setRpcSelectRequest(null)
      setRpcSelectTaskId(null)
      setRpcSelectSelectedIndex(null)
      setRpcSelectRemainingSeconds(null)
      return
    }
    setRpcSelectRequest(null)
    setRpcSelectTaskId(null)
    setRpcSelectSelectedIndex(null)
    setRpcSelectRemainingSeconds(null)
  }, [rpcSelectRequest, rpcSelectTaskId, showError])

  const runMetadataPlugin = React.useCallback(async () => {
    if (!canEdit) {
      showError(t('library.loginRequired'))
      return
    }
    if (!selectedMetadataPlugin) {
      showError(t('archive.metadataPluginSelectRequired'))
      return
    }

    setIsMetadataPluginRunning(true)
    setMetadataPluginProgress(0)
    setMetadataPluginMessage(t('archive.metadataPluginEnqueued'))
    resolvedRpcSelectRequestIdsRef.current.clear()
    setRpcSelectRequest(null)
    setRpcSelectTaskId(null)
    setRpcSelectSelectedIndex(null)
    setRpcSelectRemainingSeconds(null)

    try {
      const metadataTags = editTags.map((tag) => tag.trim()).filter(Boolean)
      const targetType = type === 'archive' ? 'archive' : 'tankoubon'
      const finalTask = await ArchiveService.runMetadataPluginForTarget(
        targetType,
        id,
        selectedMetadataPlugin,
        metadataPluginParam,
        {
          onUpdate: (task) => {
            setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0)
            setMetadataPluginMessage(task.message || '')

            const req = parseRpcSelectRequest(task.message || '')
            if (req) {
              if (resolvedRpcSelectRequestIdsRef.current.has(req.request_id)) return
              setRpcSelectTaskId(task.id)
              setRpcSelectRequest((current) => {
                if (current?.request_id === req.request_id) return current
                const defaultIndex = typeof req.default_index === 'number' ? req.default_index : 0
                setRpcSelectSelectedIndex(defaultIndex >= 0 && defaultIndex < req.options.length ? defaultIndex : 0)
                const timeout = typeof req.timeout_seconds === 'number' && req.timeout_seconds > 0 ? Math.floor(req.timeout_seconds) : 90
                setRpcSelectRemainingSeconds(timeout)
                return req
              })
            }
          },
        },
        {
          writeBack: false,
          metadata: {
            title: editTitle.trim() || displayTitle,
            type: targetType === 'tankoubon' ? 1 : 0,
            description: editSummary.trim(),
            tags: metadataTags,
            assets: [],
            archive: [],
          },
        }
      )

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed')
        showError(err)
        return
      }

      try {
        const out = finalTask.result ? JSON.parse(finalTask.result) : null
        const ok = out?.success === true || out?.success === 1 || out?.success === '1' || out?.success === 'true'
        if (!ok) {
          const err = out?.error || finalTask.result || finalTask.message || t('archive.metadataPluginFailed')
          showError(err)
          return
        }

        const data = out?.data || {}
        const readAssetValue = (assets: unknown, key: string): string => {
          if (!Array.isArray(assets)) return ''
          for (const item of assets) {
            if (!item || typeof item !== 'object') continue
            const row = item as Record<string, unknown>
            const itemKey = String(row.key ?? row.type ?? row.name ?? '').trim().toLowerCase()
            if (itemKey !== key) continue
            const value = row.value
            if (typeof value === 'number' && Number.isFinite(value)) return String(Math.trunc(value))
            if (typeof value === 'string') return value.trim()
            return ''
          }
          return ''
        }
        const nextTitle =
          typeof data.title === 'string'
            ? data.title
            : ''
        const nextSummary = typeof data.description === 'string' ? data.description : ''
        const nextTags = Array.isArray(data.tags)
          ? data.tags.map((tag: unknown) => String(tag || '').trim()).filter(Boolean)
          : []
        const nextArchives = Array.isArray(data.archive) ? data.archive : []

        if (nextTitle.trim()) setEditTitle(nextTitle.trim())
        setEditSummary(nextSummary)
        setEditTags(nextTags)
        if (type === 'tankoubon') {
          setMetadataArchivePatches(
            nextArchives
              .map((item: any) => ({
                archive_id: typeof item?.archive_id === 'string' ? item.archive_id : undefined,
                volume_no: typeof item?.volume_no === 'number' ? item.volume_no : undefined,
                title: typeof item?.title === 'string' ? item.title : undefined,
                summary: typeof item?.description === 'string' ? item.description : undefined,
                tags: Array.isArray(item?.tags)
                  ? item.tags.map((tag: unknown) => String(tag || '').trim()).filter(Boolean).join(', ')
                  : undefined,
                updated_at: typeof item?.updated_at === 'string' ? item.updated_at : undefined,
                cover: readAssetValue(item?.assets, 'cover') || undefined,
              }))
              .filter((item: any) => item.archive_id || item.volume_no)
          )
        }
      } catch {
        // Ignore parse errors and keep the task result visible in the status line.
      }

      setMetadataPluginMessage(t('archive.metadataPluginCompleted'))
      setMetadataPluginProgress(100)
    } catch (error: any) {
      logger.operationFailed('run metadata plugin (card)', error, { id, type })
      showError(error?.message || t('archive.metadataPluginFailed'))
    } finally {
      setIsMetadataPluginRunning(false)
      setRpcSelectRequest(null)
      setRpcSelectTaskId(null)
      setRpcSelectSelectedIndex(null)
      setRpcSelectRemainingSeconds(null)
    }
  }, [
    canEdit,
    displayTitle,
    editSummary,
    editTags,
    editTitle,
    id,
    metadataPluginParam,
    selectedMetadataPlugin,
    showError,
    t,
    type,
  ])

  const handleSaveEdit = React.useCallback(async () => {
    if (editSaving) return
    if (!canEdit) {
      showError(t('library.loginRequired'))
      return
    }

    const nextTitle = editTitle.trim()
    if (type === 'tankoubon' && !nextTitle) {
      showError(t('tankoubon.nameRequired'))
      return
    }

    setEditSaving(true)
    try {
      const nextTags = editTags.map((tag) => tag.trim()).filter(Boolean).join(', ')
      const nextSummary = editSummary.trim()

      if (type === 'archive') {
        await ArchiveService.updateMetadata(id, {
          title: nextTitle || displayTitle,
          summary: nextSummary,
          tags: nextTags,
        }, undefined, { metadataNamespace: selectedMetadataPlugin || undefined })
      } else {
        await TankoubonService.updateTankoubon(id, {
          name: nextTitle,
          summary: nextSummary,
          tags: nextTags,
          metadata_namespace: selectedMetadataPlugin || undefined,
          archives: metadataArchivePatches,
        })
      }

      if (nextTitle) setDisplayTitle(nextTitle)
      setDisplaySummary(nextSummary)
      setDisplayTags(nextTags)
      setEditOpen(false)
      emitRefresh()
    } catch (error) {
      logger.operationFailed('save card edit', error, { id, type })
      showError(type === 'archive' ? t('archive.updateFailed') : t('common.error'))
    } finally {
      setEditSaving(false)
    }
  }, [canEdit, displayTitle, editSaving, editSummary, editTags, editTitle, emitRefresh, id, metadataArchivePatches, selectedMetadataPlugin, showError, t, type])

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

  const readStatusLabel = isNew ? t('archive.markAsRead') : t('archive.markAsNew')
  const readStatusText = isNewStatusLoading ? t('common.loading') : readStatusLabel
  const menuActionDisabled = deleting || editSaving

  return (
    <>
      <DropdownMenu open={menuOpen} onOpenChange={setMenuOpen}>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-hidden
            className="pointer-events-none fixed h-0 w-0 opacity-0"
            style={{ left: menuPosition.x, top: menuPosition.y }}
          />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" side="bottom" className="w-52">
          <DropdownMenuItem disabled={!readerTargetId} onSelect={() => navigateToReader()}>
            <BookOpen className="mr-2 h-4 w-4" />
            {t('archive.startReading')}
          </DropdownMenuItem>

          {type === 'archive' && (
            <>
              <DropdownMenuItem onSelect={handleDownload}>
                <Download className="mr-2 h-4 w-4" />
                {t('archive.download')}
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={menuActionDisabled || isNewStatusLoading}
                onSelect={() => {
                  void handleToggleReadStatus()
                }}
              >
                {isNew ? <CheckCircle className="mr-2 h-4 w-4" /> : <RotateCcw className="mr-2 h-4 w-4" />}
                {readStatusText}
              </DropdownMenuItem>
            </>
          )}

          <DropdownMenuItem
            disabled={menuActionDisabled || favoriteLoading || !onFavoriteToggle}
            onSelect={() => {
              void toggleFavorite()
            }}
          >
            <Heart className={`mr-2 h-4 w-4 ${isFavorite ? 'fill-current text-red-500' : ''}`} />
            {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
          </DropdownMenuItem>

          <DropdownMenuSeparator />

          <DropdownMenuItem disabled={menuActionDisabled || !canEdit} onSelect={handleOpenEdit}>
            <Edit className="mr-2 h-4 w-4" />
            {t('common.edit')}
          </DropdownMenuItem>
          <DropdownMenuItem
            disabled={menuActionDisabled || !canDelete}
            className="text-destructive focus:text-destructive"
            onSelect={() => {
              void handleDelete()
            }}
          >
            <Trash2 className="mr-2 h-4 w-4" />
            {deleting ? t('common.loading') : t('common.delete')}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <div
        className={[
          "group cursor-pointer motion-reduce:animate-none",
          shouldEntranceAnimate ? "motion-safe:animate-archive-card-in" : "",
        ].filter(Boolean).join(" ")}
        // `content-visibility` acts like browser-level virtualization for large grids.
        style={{
          animationDelay: shouldEntranceAnimate ? `${animationDelay}ms` : undefined,
          ...(disableContentVisibility
            ? {}
            : {
                contentVisibility: 'auto',
                containIntrinsicSize: '220px 420px',
              }),
        }}
        title={hoverTitleParts.length > 0 ? `${displayTitle}\n${hoverTitleParts.join('\n')}` : displayTitle}
        onClick={navigateToReader}
        onContextMenu={handleContextMenu}
      >
        <Card className="overflow-hidden transition-shadow hover:shadow-lg">
          <div className="aspect-[3/4] bg-muted relative">
            {!imageError && hasImage ? (
              <Image
                src={imageSrc}
                alt={displayTitle}
                fill
                className="object-cover"
                priority={priority}
                sizes="(max-width: 640px) 50vw, (max-width: 768px) 33vw, (max-width: 1024px) 25vw, (max-width: 1280px) 20vw, 16vw"
                decoding="async"
                onError={() => setImageError(true)}
              />
            ) : (
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-muted-foreground">{t('archive.noCover')}</span>
              </div>
            )}

            {/* Badges */}
            {badge && <div className="absolute top-2 left-2 z-30">{badge}</div>}
            {isNew && (
              <Badge className="absolute top-2 right-2 z-30 bg-red-500">
                {t('archive.new')}
              </Badge>
            )}
            {extraBadge && <div className="absolute bottom-2 right-2 z-30">{extraBadge}</div>}

            {/* Floating actions (details/favorite) */}
            <div
              className={[
                // Align with the tag/summary padding (`p-3`) so chips and buttons share the same left edge.
                "absolute bottom-3 left-3 z-20 items-center gap-2",
                // Default hidden on all viewports; show on hover/focus for pointer devices.
                "flex opacity-0 translate-y-1 transition-all",
                "group-hover:opacity-100 group-hover:translate-y-0",
                "group-focus-within:opacity-100 group-focus-within:translate-y-0",
              ].filter(Boolean).join(" ")}
              onClick={(e) => e.stopPropagation()}
            >
              <Button
                asChild
                size="icon"
                variant="secondary"
                className="h-8 w-8 bg-white/15 text-white backdrop-blur-sm hover:bg-white/25"
                aria-label={detailsLabel || t('archive.details')}
                title={detailsLabel || t('archive.details')}
              >
                {/* Avoid prefetching N distinct URLs like `/archive?id=...` for large grids. */}
                <Link href={detailPath} prefetch={false}>
                  <Eye className="h-4 w-4" />
                </Link>
              </Button>
              <Button
                type="button"
                size="icon"
                variant="secondary"
                className={[
                  "h-8 w-8 bg-white/15 text-white backdrop-blur-sm hover:bg-white/25",
                  isFavorite ? "text-red-400" : "",
                ].filter(Boolean).join(" ")}
                aria-label={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                disabled={favoriteLoading}
                onClick={handleFavoriteClick}
              >
                <Heart className={`h-4 w-4 ${isFavorite ? 'fill-current' : ''}`} />
              </Button>
            </div>

            {/* Hover overlay (also acts as a scrim behind floating actions when there are no tags/summary) */}
            <div
              className={[
                "pointer-events-none absolute inset-0 z-10 flex items-end bg-gradient-to-t from-black/70 via-black/30 to-transparent transition-opacity",
                // Default hidden on all viewports; show on hover/focus behind floating actions / tag chips.
                "opacity-0 group-hover:opacity-100 group-focus-within:opacity-100",
              ].join(" ")}
            >
              {(allTags.length > 0 || displaySummary) && (
                <div className="w-full p-3 pb-12 space-y-2">
                  {/* Reserve space for the floating action buttons on all viewports (mobile has no hover). */}
                  {allTags.length > 0 && (
                    <div
                      className={[
                        "flex flex-wrap gap-1 overflow-hidden",
                        displaySummary ? "max-h-[48px]" : "max-h-[72px]",
                      ].join(" ")}
                    >
                      {hoverTags.map((tag) => (
                        <span key={tag} className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-sm">
                          {stripNamespace(tag)}
                        </span>
                      ))}
                      {allTags.length > hoverTags.length && (
                        <span className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-sm">
                          +{allTags.length - hoverTags.length}
                        </span>
                      )}
                    </div>
                  )}
                  {displaySummary && (
                    <div className="text-[11px] leading-snug text-white/90 line-clamp-3">{displaySummary}</div>
                  )}
                </div>
              )}
            </div>
          </div>
        </Card>

        {/* Keep the white "card" background scoped to the cover only; meta text renders outside. */}
        <div className="pt-3">
          <div className="h-5 mb-2">
            <h3 className="font-semibold text-sm line-clamp-1" title={displayTitle}>
              {displayTitle}
            </h3>
          </div>
          <div className={["text-xs text-muted-foreground", hideMetaOnMobile ? "hidden sm:block" : ""].join(" ")}>
            {pagesLabel || t('archive.pages').replace('{count}', String(pagecount))}
            {progress > 0 && pagecount > 0 && ` • ${progressPercent}% ${t('common.read')}`}
          </div>
        </div>
      </div>

      <ArchiveMetadataEditDialog
        open={editOpen}
        onOpenChange={setEditOpen}
        t={t}
        dialogTitle={type === 'archive' ? t('archive.editMetadata') : t('tankoubon.editTankoubon')}
        titleLabel={type === 'archive' ? t('archive.titleField') : t('tankoubon.name')}
        summaryLabel={type === 'archive' ? t('archive.summary') : t('tankoubon.summary')}
        tagsLabel={type === 'archive' ? t('archive.tags') : t('tankoubon.tags')}
        summaryPlaceholder={type === 'archive' ? t('archive.summaryPlaceholder') : t('tankoubon.summaryPlaceholder')}
        tagsPlaceholder={type === 'archive' ? t('archive.tagsPlaceholder') : t('tankoubon.tagsPlaceholder')}
        title={editTitle}
        onTitleChange={setEditTitle}
        summary={editSummary}
        onSummaryChange={setEditSummary}
        tags={editTags}
        onTagsChange={setEditTags}
        isSaving={editSaving}
        saveDisabled={type === 'tankoubon' ? !editTitle.trim() : false}
        onSave={handleSaveEdit}
        showMetadataPlugin
        metadataPlugins={metadataPlugins}
        selectedMetadataPlugin={selectedMetadataPlugin}
        onSelectedMetadataPluginChange={setSelectedMetadataPlugin}
        metadataPluginParam={metadataPluginParam}
        onMetadataPluginParamChange={setMetadataPluginParam}
        isMetadataPluginRunning={isMetadataPluginRunning}
        metadataPluginProgress={metadataPluginProgress}
        metadataPluginMessage={metadataPluginMessage}
        onRunMetadataPlugin={runMetadataPlugin}
        rpcSelect={{
          request: rpcSelectRequest,
          selectedIndex: rpcSelectSelectedIndex,
          remainingSeconds: rpcSelectRemainingSeconds,
          onSelectIndex: setRpcSelectSelectedIndex,
          onAbort: abortRpcSelect,
          onSubmit: submitRpcSelect,
        }}
      />
    </>
  )
}
