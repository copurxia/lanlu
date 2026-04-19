"use client"

import * as React from 'react'
import { ArchiveMetadataEditDialog } from '@/components/archive/ArchiveMetadataEditDialog'
import type { BaseMediaCardType } from '@/components/ui/base-media-card.types'
import { useLanguage } from '@/contexts/LanguageContext'
import { useToast } from '@/hooks/use-toast'
import { ArchiveService } from '@/lib/services/archive-service'
import { ChunkedUploadService } from '@/lib/services/chunked-upload-service'
import { PluginService } from '@/lib/services/plugin-service'
import { TankoubonService } from '@/lib/services/tankoubon-service'
import { TaskPoolService } from '@/lib/services/taskpool-service'
import { getCoverAssetId } from '@/lib/utils/archive-assets'
import { appEvents, AppEvents } from '@/lib/utils/events'
import { logger } from '@/lib/utils/logger'
import { buildMetadataAssetInputs } from '@/lib/utils/metadata'
import { extractApiError } from '@/lib/utils/api-utils'
import {
  applyAssetPreviewValue,
  normalizeMetadataPluginChildren,
  normalizeMetadataPluginTags,
  parseMetadataAssetId,
  parseMetadataPluginPreviewResult,
  parseMetadataPluginRpcSelectRequest,
  splitMetadataTagList,
} from '@/lib/utils/metadata-plugin-preview'
import type { Plugin } from '@/lib/services/plugin-service'
import type { MetadataPagePatch } from '@/types/archive'
import type { RpcSelectRequest } from '@/types/metadata-plugin'
import type { TankoubonMemberMetadataPatch } from '@/types/tankoubon'

type BaseMediaCardEditControllerProps = {
  id: string
  initialSummary: string
  initialTags: string
  initialTitle: string
  onOpenChange: (open: boolean) => void
  onSaved: (next: { summary: string; tags: string; title: string }) => void
  thumbnailAssetId?: number
  type: BaseMediaCardType
}

export function BaseMediaCardEditController({
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
  const [editTags, setEditTags] = React.useState<string[]>(() => splitMetadataTagList(initialTags))
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
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = React.useState('')
  const [metadataPluginParam, setMetadataPluginParam] = React.useState('')
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

  const clearRpcSelectState = React.useCallback(() => {
    setRpcSelectRequest(null)
    setRpcSelectTaskId(null)
    setRpcSelectSelectedIndex(null)
    setRpcSelectRemainingSeconds(null)
  }, [])

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
      clearRpcSelectState()
      return
    }

    const timer = window.setTimeout(() => {
      setRpcSelectRemainingSeconds((current) => {
        if (current == null) return null
        return Math.max(0, current - 1)
      })
    }, 1000)

    return () => window.clearTimeout(timer)
  }, [clearRpcSelectState, rpcSelectRemainingSeconds, rpcSelectRequest])

  React.useEffect(() => {
    const fallbackCoverId =
      typeof thumbnailAssetId === 'number' && Number.isFinite(thumbnailAssetId) && thumbnailAssetId > 0
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
      clearRpcSelectState()
      return
    }
    clearRpcSelectState()
  }, [clearRpcSelectState, rpcSelectRequest, rpcSelectSelectedIndex, rpcSelectTaskId, showError])

  const abortRpcSelect = React.useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest) return
    const requestId = rpcSelectRequest.request_id
    const ok = await TaskPoolService.abortRpcSelect(rpcSelectTaskId, requestId)
    resolvedRpcSelectRequestIdsRef.current.add(requestId)
    if (!ok) {
      showError('放弃选择失败，可能请求已过期')
      clearRpcSelectState()
      return
    }
    clearRpcSelectState()
  }, [clearRpcSelectState, rpcSelectRequest, rpcSelectTaskId, showError])

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
      const nativeEvent = event as unknown as React.ChangeEvent<HTMLInputElement>
      const file = nativeEvent.target.files?.[0]
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
      } catch (error) {
        logger.operationFailed('upload metadata asset from card', error, { id, slot, type })
        showError(extractApiError(error, t('archive.assetUploadFailed')))
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
    clearRpcSelectState()

    try {
      const metadataTags = normalizeMetadataPluginTags(editTags)
      const targetType = type === 'archive' ? 'archive' : 'tankoubon'
      const rootAssets = buildMetadataAssetInputs(
        {
          cover: editCover || undefined,
          backdrop: editBackdrop || undefined,
          clearlogo: editClearlogo || undefined,
        },
        {
          cover: parseMetadataAssetId(editAssetCoverId),
          backdrop: parseMetadataAssetId(editAssetBackdropId),
          clearlogo: parseMetadataAssetId(editAssetClearlogoId),
        }
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

            const request = parseMetadataPluginRpcSelectRequest(task.message || '')
            if (!request || resolvedRpcSelectRequestIdsRef.current.has(request.request_id)) return

            setRpcSelectTaskId(task.id)
            setRpcSelectRequest((current) => {
              if (current?.request_id === request.request_id) return current
              const defaultIndex = typeof request.default_index === 'number' ? request.default_index : 0
              setRpcSelectSelectedIndex(defaultIndex >= 0 && defaultIndex < request.options.length ? defaultIndex : 0)
              const timeout =
                typeof request.timeout_seconds === 'number' && request.timeout_seconds > 0
                  ? Math.floor(request.timeout_seconds)
                  : 90
              setRpcSelectRemainingSeconds(timeout)
              return request
            })
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
            children:
              type === 'tankoubon'
                ? metadataArchivePatches.map((item) => ({
                    title: String(item.title || '').trim(),
                    type: 0,
                    description: String(item.summary || item.description || '').trim(),
                    tags: Array.isArray(item.tags) ? item.tags : splitMetadataTagList(item.tags),
                    assets: buildMetadataAssetInputs({
                      cover: item.cover || undefined,
                      backdrop: item.backdrop || undefined,
                      clearlogo: item.clearlogo || undefined,
                    }),
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
        showError(finalTask.result || finalTask.message || t('archive.metadataPluginFailed'))
        return
      }

      const previewResult = parseMetadataPluginPreviewResult(finalTask.result)
      if (!previewResult.ok) {
        if (!previewResult.parseFailed) {
          showError(previewResult.error || finalTask.result || finalTask.message || t('archive.metadataPluginFailed'))
        }
        return
      }

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
        setMetadataArchivePatches(normalizeMetadataPluginChildren(nextData.children))
      }

      setMetadataPluginMessage(t('archive.metadataPluginCompleted'))
      setMetadataPluginProgress(100)
    } catch (error) {
      logger.operationFailed('run metadata plugin (card)', error, { id, type })
      showError(extractApiError(error, t('archive.metadataPluginFailed')))
    } finally {
      setIsMetadataPluginRunning(false)
      clearRpcSelectState()
    }
  }, [
    clearRpcSelectState,
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
      const nextTags = normalizeMetadataPluginTags(editTags)
      const nextSummary = editSummary.trim()
      const assetIds = {
        cover: parseMetadataAssetId(editAssetCoverId),
        backdrop: parseMetadataAssetId(editAssetBackdropId),
        clearlogo: parseMetadataAssetId(editAssetClearlogoId),
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
            assetIds
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
            assetIds
          ),
          metadata_namespace: selectedMetadataPlugin || undefined,
          children: metadataArchivePatches.map((item) => ({
            title: String(item.title || '').trim(),
            type: 0,
            description: String(item.summary || item.description || '').trim(),
            tags: Array.isArray(item.tags) ? item.tags : splitMetadataTagList(item.tags),
            assets: buildMetadataAssetInputs({
              cover: item.cover || undefined,
              backdrop: item.backdrop || undefined,
              clearlogo: item.clearlogo || undefined,
            }),
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
