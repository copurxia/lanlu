"use client"

import * as React from "react"
import { useRouter } from 'next/navigation'
import Image from 'next/image'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { BookOpen, Check, CheckCircle, Download, Edit, Eye, Heart, RotateCcw, Square, Trash2 } from 'lucide-react'
import { ArchiveService } from '@/lib/services/archive-service'
import { TankoubonService } from '@/lib/services/tankoubon-service'
import { ChunkedUploadService } from '@/lib/services/chunked-upload-service'
import { TaskPoolService } from '@/lib/services/taskpool-service'
import { PluginService } from '@/lib/services/plugin-service'
import { ArchiveMetadataEditDialog, type RpcSelectRequest } from '@/components/archive/ArchiveMetadataEditDialog'
import { useLanguage } from '@/contexts/LanguageContext'
import { useAuth } from '@/contexts/AuthContext'
import { useToast } from '@/hooks/use-toast'
import { useConfirmContext } from '@/contexts/ConfirmProvider'
import { appEvents, AppEvents } from '@/lib/utils/events'
import { logger } from '@/lib/utils/logger'
import { buildReaderPath } from '@/lib/utils/reader'
import { stripNamespace, parseTags } from '@/lib/utils/tag-utils'
import { getCoverAssetId } from '@/lib/utils/archive-assets'
import { buildMetadataAssetInputs, normalizeTankoubonMemberMetadataPatch } from '@/lib/utils/metadata'
import { applyAssetPreviewValue, parseMetadataPluginPreviewResult } from '@/lib/utils/metadata-plugin-preview'
import type { MetadataPagePatch } from '@/types/archive'
import type { TankoubonMemberMetadataPatch } from '@/types/tankoubon'
import type { Plugin } from '@/lib/services/plugin-service'
import type { RecommendationItemType, RecommendationScene } from '@/types/recommendation'

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
  coverHeight?: number

  // 收藏回调
  onFavoriteToggle?: (id: string, isFavorite: boolean) => Promise<boolean>
  selectable?: boolean
  selectionMode?: boolean
  selected?: boolean
  onToggleSelect?: (selected: boolean) => void
  onRequestEnterSelection?: () => void
  onCoverAspectRatioChange?: (aspectRatio: number) => void
  recommendationContext?: {
    scene: RecommendationScene
    seedEntityType?: RecommendationItemType
    seedEntityId?: string
  }
  onRecommendationOpenReader?: (itemType: RecommendationItemType, itemId: string) => void
  onRecommendationOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void
  onRecommendationFavorite?: (itemType: RecommendationItemType, itemId: string) => void
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

type BaseMediaCardEditControllerProps = {
  id: string
  initialSummary: string
  initialTags: string
  initialTitle: string
  onOpenChange: (open: boolean) => void
  onSaved: (next: { summary: string; tags: string; title: string }) => void
  thumbnailAssetId?: number
  type: 'archive' | 'tankoubon'
}

function BaseMediaCardEditController({
  id,
  initialSummary,
  initialTags,
  initialTitle,
  onOpenChange,
  onSaved,
  thumbnailAssetId,
  type,
}: BaseMediaCardEditControllerProps) {
  const { t } = useLanguage()
  const { error: showError } = useToast()
  const [editSaving, setEditSaving] = React.useState(false)
  const [editTitle, setEditTitle] = React.useState(initialTitle)
  const [editSummary, setEditSummary] = React.useState(initialSummary)
  const [editTags, setEditTags] = React.useState<string[]>(() => toTagList(initialTags))
  const [editCover, setEditCover] = React.useState('')
  const [editBackdrop, setEditBackdrop] = React.useState('')
  const [editClearlogo, setEditClearlogo] = React.useState('')
  const [editAssetCoverId, setEditAssetCoverId] = React.useState('')
  const [editAssetBackdropId, setEditAssetBackdropId] = React.useState('')
  const [editAssetClearlogoId, setEditAssetClearlogoId] = React.useState('')
  const [coverUploading, setCoverUploading] = React.useState(false)
  const [backdropUploading, setBackdropUploading] = React.useState(false)
  const [clearlogoUploading, setClearlogoUploading] = React.useState(false)
  const [metadataPlugins, setMetadataPlugins] = React.useState<Plugin[]>([])
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = React.useState<string>('')
  const [metadataPluginParam, setMetadataPluginParam] = React.useState<string>('')
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = React.useState(false)
  const [metadataPluginProgress, setMetadataPluginProgress] = React.useState<number | null>(null)
  const [metadataPluginMessage, setMetadataPluginMessage] = React.useState('')
  const [metadataArchivePatches, setMetadataArchivePatches] = React.useState<TankoubonMemberMetadataPatch[]>([])
  const [metadataPreviewPages, setMetadataPreviewPages] = React.useState<MetadataPagePatch[]>([])
  const [rpcSelectTaskId, setRpcSelectTaskId] = React.useState<number | null>(null)
  const [rpcSelectRequest, setRpcSelectRequest] = React.useState<RpcSelectRequest | null>(null)
  const [rpcSelectSelectedIndex, setRpcSelectSelectedIndex] = React.useState<number | null>(null)
  const [rpcSelectRemainingSeconds, setRpcSelectRemainingSeconds] = React.useState<number | null>(null)
  const resolvedRpcSelectRequestIdsRef = React.useRef<Set<string>>(new Set())

  React.useEffect(() => {
    let cancelled = false

    ;(async () => {
      try {
        const metas = await PluginService.getMetadataPlugins()
        if (cancelled) return
        setMetadataPlugins(metas)
        if (metas.length > 0) {
          setSelectedMetadataPlugin((current) => current || metas[0].namespace)
        }
      } catch (error) {
        logger.apiError('load metadata plugins (card)', error)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [])

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

  React.useEffect(() => {
    const fallbackCoverId = typeof thumbnailAssetId === 'number' && Number.isFinite(thumbnailAssetId) && thumbnailAssetId > 0
      ? String(Math.trunc(thumbnailAssetId))
      : ''
    setEditAssetCoverId(fallbackCoverId)
    setEditAssetBackdropId('')
    setEditAssetClearlogoId('')

    let cancelled = false
    ;(async () => {
      try {
        if (type === 'archive') {
          const meta = await ArchiveService.getMetadata(id)
          if (cancelled) return
          setEditAssetCoverId(String(getCoverAssetId(meta) || ''))
          setEditAssetBackdropId(String(meta.assets?.backdrop || ''))
          setEditAssetClearlogoId(String(meta.assets?.clearlogo || ''))
          return
        }

        const tank = await TankoubonService.getMetadata(id)
        if (cancelled) return
        setEditAssetCoverId(String(getCoverAssetId(tank) || ''))
        setEditAssetBackdropId(String(tank.assets?.backdrop || ''))
        setEditAssetClearlogoId(String(tank.assets?.clearlogo || ''))
      } catch {
        // Keep fallback values when detail request fails.
      }
    })()

    return () => {
      cancelled = true
    }
  }, [id, thumbnailAssetId, type])

  const emitRefresh = React.useCallback(() => {
    appEvents.emit(AppEvents.ARCHIVES_REFRESH)
  }, [])

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

  const uploadMetadataAsset = React.useCallback((slot: 'cover' | 'backdrop' | 'clearlogo') => {
    if (editSaving || isMetadataPluginRunning) return

    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/*'
    input.style.display = 'none'

    const setUploading = (next: boolean) => {
      if (slot === 'cover') {
        setCoverUploading(next)
        return
      }
      if (slot === 'backdrop') {
        setBackdropUploading(next)
        return
      }
      setClearlogoUploading(next)
    }

    input.onchange = async (event) => {
      const e = event as unknown as React.ChangeEvent<HTMLInputElement>
      const file = e.target.files?.[0]
      if (!file) {
        document.body.removeChild(input)
        return
      }

      setUploading(true)
      try {
        const result = await ChunkedUploadService.uploadWithChunks(
          file,
          {
            targetType: 'metadata_asset',
            overwrite: true,
            contentType: file.type || 'application/octet-stream',
          },
          {
            onProgress: () => {},
            onChunkComplete: () => {},
            onError: () => {},
          }
        )
        if (!result.success) {
          throw new Error(result.error || t('archive.assetUploadFailed'))
        }

        const assetId = Number(result.data?.assetId ?? 0)
        if (!Number.isFinite(assetId) || assetId <= 0) {
          throw new Error(t('archive.assetUploadFailed'))
        }
        const normalizedAssetId = String(Math.trunc(assetId))

        if (slot === 'cover') {
          setEditAssetCoverId(normalizedAssetId)
          setEditCover('')
        } else if (slot === 'backdrop') {
          setEditAssetBackdropId(normalizedAssetId)
          setEditBackdrop('')
        } else {
          setEditAssetClearlogoId(normalizedAssetId)
          setEditClearlogo('')
        }
      } catch (error: any) {
        logger.operationFailed('upload metadata asset from card', error, { id, slot, type })
        showError(error?.response?.data?.message || error?.message || t('archive.assetUploadFailed'))
      } finally {
        setUploading(false)
        document.body.removeChild(input)
      }
    }

    document.body.appendChild(input)
    input.click()
  }, [editSaving, id, isMetadataPluginRunning, showError, t, type])

  const runMetadataPlugin = React.useCallback(async () => {
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
      const rootAssets = buildMetadataAssetInputs(
        {
          cover: editCover || undefined,
          backdrop: editBackdrop || undefined,
          clearlogo: editClearlogo || undefined,
        },
        {
          cover: /^\d+$/.test(editAssetCoverId.trim()) ? Number.parseInt(editAssetCoverId.trim(), 10) : undefined,
          backdrop: /^\d+$/.test(editAssetBackdropId.trim()) ? Number.parseInt(editAssetBackdropId.trim(), 10) : undefined,
          clearlogo: /^\d+$/.test(editAssetClearlogoId.trim()) ? Number.parseInt(editAssetClearlogoId.trim(), 10) : undefined,
        },
      ) || []
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
            title: editTitle.trim() || initialTitle,
            type: targetType === 'tankoubon' ? 1 : 0,
            description: editSummary.trim(),
            tags: metadataTags,
            assets: rootAssets,
            children: type === 'tankoubon'
              ? metadataArchivePatches.map((item) => ({
                  title: String(item.title || '').trim(),
                  type: 0,
                  description: String(item.summary || item.description || '').trim(),
                  tags: Array.isArray(item.tags)
                    ? item.tags
                    : String(item.tags || '')
                        .split(',')
                        .map((tag) => tag.trim())
                        .filter(Boolean),
                  assets: buildMetadataAssetInputs(
                    {
                      cover: item.cover || undefined,
                      backdrop: item.backdrop || undefined,
                      clearlogo: item.clearlogo || undefined,
                    },
                  ),
                  archive_id: item.archive_id,
                  volume_no: item.volume_no,
                  updated_at: item.updated_at,
                  pages: item.pages,
                }))
              : [],
          },
        }
      )

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed')
        showError(err)
        return
      }

      const previewResult = parseMetadataPluginPreviewResult(finalTask.result)
      if (!previewResult.ok) {
        if (!previewResult.parseFailed) {
          const err = previewResult.error || finalTask.result || finalTask.message || t('archive.metadataPluginFailed')
          showError(err)
          return
        }
      } else {
        const nextData = previewResult.data
        if (nextData.title.trim()) setEditTitle(nextData.title.trim())
        setEditSummary(nextData.summary)
        setEditTags(nextData.tags)
        applyAssetPreviewValue(nextData.cover, setEditCover, setEditAssetCoverId)
        applyAssetPreviewValue(nextData.backdrop, setEditBackdrop, setEditAssetBackdropId)
        applyAssetPreviewValue(nextData.clearlogo, setEditClearlogo, setEditAssetClearlogoId)
        if (type === 'archive') {
          setMetadataPreviewPages(nextData.pages)
        }
        if (type === 'tankoubon') {
          setMetadataArchivePatches(
            nextData.children
              .map((item: unknown) => normalizeTankoubonMemberMetadataPatch(item))
              .filter((item: TankoubonMemberMetadataPatch) => item.archive_id || item.volume_no)
          )
        }
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
    editAssetBackdropId,
    editAssetClearlogoId,
    editAssetCoverId,
    editBackdrop,
    editClearlogo,
    editCover,
    editSummary,
    editTags,
    editTitle,
    id,
    initialTitle,
    metadataArchivePatches,
    metadataPluginParam,
    selectedMetadataPlugin,
    showError,
    t,
    type,
  ])

  const handleSaveEdit = React.useCallback(async () => {
    if (editSaving) return

    const nextTitle = editTitle.trim()
    if (type === 'tankoubon' && !nextTitle) {
      showError(t('tankoubon.nameRequired'))
      return
    }

    setEditSaving(true)
    try {
      const nextTags = editTags.map((tag) => tag.trim()).filter(Boolean)
      const nextSummary = editSummary.trim()
      const parseAssetId = (raw: string): number | undefined => {
        const value = Number(raw.trim())
        if (!Number.isFinite(value)) return undefined
        const parsedId = Math.trunc(value)
        return parsedId > 0 ? parsedId : undefined
      }
      const assetIds = {
        cover: parseAssetId(editAssetCoverId),
        backdrop: parseAssetId(editAssetBackdropId),
        clearlogo: parseAssetId(editAssetClearlogoId),
      }

      if (type === 'archive') {
        await ArchiveService.updateMetadata(id, {
          title: nextTitle || initialTitle,
          type: 0,
          description: nextSummary,
          tags: nextTags,
          assets: buildMetadataAssetInputs(
            {
              cover: editCover || undefined,
              backdrop: editBackdrop || undefined,
              clearlogo: editClearlogo || undefined,
            },
            assetIds,
          ),
          pages: metadataPreviewPages.length > 0 ? metadataPreviewPages : undefined,
          metadata_namespace: selectedMetadataPlugin || undefined,
        })
      } else {
        await TankoubonService.updateMetadata(id, {
          title: nextTitle,
          type: 1,
          description: nextSummary,
          tags: nextTags,
          assets: buildMetadataAssetInputs(
            {
              cover: editCover || undefined,
              backdrop: editBackdrop || undefined,
              clearlogo: editClearlogo || undefined,
            },
            assetIds,
          ),
          metadata_namespace: selectedMetadataPlugin || undefined,
          children: metadataArchivePatches.map((item) => ({
            title: String(item.title || '').trim(),
            type: 0,
            description: String(item.summary || item.description || '').trim(),
            tags: Array.isArray(item.tags)
              ? item.tags
              : String(item.tags || '')
                  .split(',')
                  .map((tag) => tag.trim())
                  .filter(Boolean),
            assets: buildMetadataAssetInputs(
              {
                cover: item.cover || undefined,
                backdrop: item.backdrop || undefined,
                clearlogo: item.clearlogo || undefined,
              },
            ),
            archive_id: typeof item.archive_id === 'string' ? item.archive_id : undefined,
            volume_no: item.volume_no,
            updated_at: typeof item.updated_at === 'string' ? item.updated_at : undefined,
            pages: item.pages,
          })),
        })
      }

      onSaved({
        title: nextTitle || initialTitle,
        summary: nextSummary,
        tags: nextTags.join(', '),
      })
      onOpenChange(false)
      emitRefresh()
    } catch (error) {
      logger.operationFailed('save card edit', error, { id, type })
      showError(type === 'archive' ? t('archive.updateFailed') : t('common.error'))
    } finally {
      setEditSaving(false)
    }
  }, [
    editAssetBackdropId,
    editAssetClearlogoId,
    editAssetCoverId,
    editBackdrop,
    editClearlogo,
    editCover,
    editSaving,
    editSummary,
    editTags,
    editTitle,
    emitRefresh,
    id,
    initialTitle,
    metadataArchivePatches,
    metadataPreviewPages,
    onOpenChange,
    onSaved,
    selectedMetadataPlugin,
    showError,
    t,
    type,
  ])

  return (
    <ArchiveMetadataEditDialog
      open
      onOpenChange={onOpenChange}
      t={t}
      titleLabel={type === 'archive' ? t('archive.titleField') : t('tankoubon.name')}
      summaryLabel={type === 'archive' ? t('archive.summary') : t('tankoubon.summary')}
      tagsLabel={type === 'archive' ? t('archive.tags') : t('tankoubon.tags')}
      summaryPlaceholder={type === 'archive' ? t('archive.summaryPlaceholder') : t('tankoubon.summaryPlaceholder')}
      tagsPlaceholder={type === 'archive' ? t('archive.tagsPlaceholder') : t('tankoubon.tagsPlaceholder')}
      title={editTitle}
      onTitleChange={setEditTitle}
      summary={editSummary}
      onSummaryChange={setEditSummary}
      assetCoverId={editAssetCoverId}
      onAssetCoverIdChange={setEditAssetCoverId}
      assetBackdropId={editAssetBackdropId}
      onAssetBackdropIdChange={setEditAssetBackdropId}
      assetClearlogoId={editAssetClearlogoId}
      onAssetClearlogoIdChange={setEditAssetClearlogoId}
      assetCoverValue={editCover}
      assetBackdropValue={editBackdrop}
      assetClearlogoValue={editClearlogo}
      onUploadAssetCover={() => uploadMetadataAsset('cover')}
      onUploadAssetBackdrop={() => uploadMetadataAsset('backdrop')}
      onUploadAssetClearlogo={() => uploadMetadataAsset('clearlogo')}
      uploadingAssetCover={coverUploading}
      uploadingAssetBackdrop={backdropUploading}
      uploadingAssetClearlogo={clearlogoUploading}
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
  )
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
  coverHeight,
  onFavoriteToggle,
  selectable = false,
  selectionMode = false,
  selected = false,
  onToggleSelect,
  onRequestEnterSelection,
  onCoverAspectRatioChange,
  recommendationContext,
  onRecommendationOpenReader,
  onRecommendationOpenDetails,
  onRecommendationFavorite,
}: BaseMediaCardProps) {
  const imageSrc = thumbnailUrl && thumbnailUrl.trim().length > 0
    ? thumbnailUrl
    : ArchiveService.getAssetUrl(thumbnailAssetId)
  const hasImage = imageSrc.trim().length > 0

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
  const readerPath = readerTargetId
    ? buildReaderPath(readerTargetId, type === 'archive' ? progress : undefined)
    : detailPath
  const progressPercent = pagecount > 0 ? Math.round((progress / pagecount) * 100) : 0

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

  const emitRefresh = React.useCallback(() => {
    appEvents.emit(AppEvents.ARCHIVES_REFRESH)
  }, [])

  const navigateToReader = React.useCallback(() => {
    onRecommendationOpenReader?.(type, id)
    router.push(readerPath)
  }, [id, onRecommendationOpenReader, readerPath, router, type])

  const navigateToDetails = React.useCallback(() => {
    onRecommendationOpenDetails?.(type, id)
    router.push(detailPath)
  }, [detailPath, id, onRecommendationOpenDetails, router, type])

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
      if (success) {
        const nextFavorite = !isFavorite
        setIsFavorite(nextFavorite)
        if (nextFavorite) {
          onRecommendationFavorite?.(type, id)
        }
      }
    } catch (error) {
      logger.operationFailed('toggle favorite', error, { id, type })
    } finally {
      setFavoriteLoading(false)
    }
  }, [favoriteLoading, id, isFavorite, onFavoriteToggle, onRecommendationFavorite, type])

  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation()
    await toggleFavorite()
  }

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    if (selectionMode) return
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

  const readStatusLabel = isNew ? t('archive.markAsRead') : t('archive.markAsNew')
  const readStatusText = isNewStatusLoading ? t('common.loading') : readStatusLabel
  const menuActionDisabled = deleting

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
          {selectable && !selectionMode && (
            <>
              <DropdownMenuItem
                onSelect={() => {
                  toggleSelected(true)
                }}
              >
                <Square className="mr-2 h-4 w-4" />
                {t('home.useMultiSelect')}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
            </>
          )}
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
        onClick={(e) => {
          if (selectionMode && selectable) {
            e.preventDefault()
            toggleSelected()
            return
          }
          navigateToReader()
        }}
        onContextMenuCapture={(e) => {
          e.preventDefault()
        }}
        onContextMenu={handleContextMenu}
      >
        <Card className="overflow-hidden bg-card/70 transition-shadow hover:shadow-lg dark:bg-card/70">
          <div
            className="bg-muted relative"
            style={coverHeight != null ? { height: `${coverHeight}px` } : { aspectRatio: String(coverNaturalAspectRatio) }}
          >
            {!imageError && hasImage ? (
              <Image
                src={imageSrc}
                alt={displayTitle}
                fill
                className="object-cover select-none"
                priority={priority}
                sizes="(max-width: 640px) 50vw, (max-width: 768px) 33vw, (max-width: 1024px) 25vw, (max-width: 1280px) 20vw, 16vw"
                decoding="async"
                draggable={false}
                style={{
                  WebkitTouchCallout: 'none',
                  WebkitUserSelect: 'none',
                  userSelect: 'none',
                }}
                onLoad={handleImageLoad}
                onContextMenu={(e) => e.preventDefault()}
                onDragStart={(e) => e.preventDefault()}
                onError={() => {
                  setImageError(true)
                  setCoverNaturalAspectRatio(DEFAULT_COVER_ASPECT_RATIO)
                }}
              />
            ) : (
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-muted-foreground">{t('archive.noCover')}</span>
              </div>
            )}
            {selectionMode && !selected && (
              <div className="absolute inset-0 z-1 bg-black/45 pointer-events-none" />
            )}

            {/* Badges */}
            {badge && <div className="absolute top-2 left-2 z-30">{badge}</div>}
            {selectable && (
              <div
                className={[
                  "absolute top-2 left-2 z-40 transition-all",
                  selectionMode || selected
                    ? "opacity-100 translate-y-0 pointer-events-auto"
                    : "opacity-0 -translate-y-1 pointer-events-none md:group-hover:opacity-100 md:group-hover:translate-y-0 md:group-hover:pointer-events-auto",
                ].join(" ")}
              >
                <button
                  type="button"
                  className={[
                    "inline-flex h-7 w-7 items-center justify-center rounded-full border backdrop-blur-xs transition-colors",
                    selected
                      ? "bg-primary text-primary-foreground border-primary/60 shadow-xs"
                      : "bg-black/50 text-white border-white/40 hover:bg-black/65",
                  ].join(" ")}
                  onClick={(e) => {
                    e.stopPropagation()
                    toggleSelected()
                  }}
                  aria-label={selected ? t('home.unselectItem') : t('home.selectItem')}
                  title={selected ? t('home.unselectItem') : t('home.selectItem')}
                >
                  {selected ? <Check className="h-4 w-4" /> : <Square className="h-4 w-4" />}
                </button>
              </div>
            )}
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
                "flex",
                "opacity-0 translate-y-1 transition-all",
                "group-hover:opacity-100 group-hover:translate-y-0",
              ].filter(Boolean).join(" ")}
              onClick={(e) => e.stopPropagation()}
            >
              <Button
                size="icon"
                variant="secondary"
                className="h-8 w-8 bg-white/15 text-white backdrop-blur-xs hover:bg-white/25"
                aria-label={detailsLabel || t('archive.details')}
                title={detailsLabel || t('archive.details')}
                onClick={navigateToDetails}
              >
                <Eye className="h-4 w-4" />
              </Button>
              <Button
                type="button"
                size="icon"
                variant="secondary"
                className={[
                  "h-8 w-8 bg-white/15 text-white backdrop-blur-xs hover:bg-white/25",
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
                "pointer-events-none absolute inset-0 z-10 flex items-end bg-linear-to-t from-black/70 via-black/30 to-transparent transition-opacity",
                // Default hidden on all viewports; show on hover/focus behind floating actions / tag chips.
                "opacity-0 group-hover:opacity-100",
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
                        <span key={tag} className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-xs">
                          {stripNamespace(tag)}
                        </span>
                      ))}
                      {allTags.length > hoverTags.length && (
                        <span className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-xs">
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

      {editOpen ? (
        <BaseMediaCardEditController
          id={id}
          initialSummary={displaySummary}
          initialTags={displayTags}
          initialTitle={displayTitle}
          onOpenChange={setEditOpen}
          onSaved={({ summary, tags, title }) => {
            setDisplayTitle(title)
            setDisplaySummary(summary)
            setDisplayTags(tags)
          }}
          thumbnailAssetId={thumbnailAssetId}
          type={type}
        />
      ) : null}
    </>
  )
}
