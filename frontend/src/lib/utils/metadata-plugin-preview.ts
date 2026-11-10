import { readMetadataAssetValue } from '@/lib/utils/archive-assets'
import { isSuccessResponse } from '@/lib/utils/api-utils'
import { normalizeMetadataPages, normalizeTankoubonMemberMetadataPatch } from '@/lib/utils/metadata'
import type { MetadataPagePatch } from '@/types/archive'
import type { RpcSelectRequest } from '@/types/metadata-plugin'
import type { TankoubonMemberMetadataPatch } from '@/types/tankoubon'

export type MetadataPluginPreviewData = {
  title: string
  summary: string
  tags: string[]
  cover: string
  backdrop: string
  clearlogo: string
  children: unknown[]
  pages: MetadataPagePatch[]
}

export type MetadataPluginPreviewParseResult =
  | { ok: true; data: MetadataPluginPreviewData }
  | { ok: false; error?: string; parseFailed?: boolean }

export function parseMetadataPluginPreviewResult(rawResult: string | null | undefined): MetadataPluginPreviewParseResult {
  if (!rawResult) {
    return { ok: false, parseFailed: true }
  }

  let out: unknown
  try {
    out = JSON.parse(rawResult)
  } catch {
    return { ok: false, parseFailed: true }
  }

  if (typeof out !== 'object' || out === null) {
    return { ok: false, parseFailed: true }
  }

  const payload = out as {
    success?: unknown
    error?: unknown
    data?: {
      title?: unknown
      description?: unknown
      tags?: unknown
      assets?: unknown
      children?: unknown
      pages?: unknown
    }
  }

  if (!isSuccessResponse(payload.success)) {
    return { ok: false, error: String(payload.error || '').trim() || undefined }
  }

  const data = payload.data || {}
  const tags = Array.isArray(data.tags)
    ? data.tags.map((tag: unknown) => String(tag || '').trim()).filter(Boolean)
    : []

  return {
    ok: true,
    data: {
      title: typeof data.title === 'string' ? data.title : '',
      summary: typeof data.description === 'string' ? data.description : '',
      tags,
      cover: readMetadataAssetValue(data.assets, 'cover'),
      backdrop: readMetadataAssetValue(data.assets, 'backdrop'),
      clearlogo: readMetadataAssetValue(data.assets, 'clearlogo'),
      children: Array.isArray(data.children) ? data.children : [],
      pages: normalizeMetadataPages(data.pages),
    },
  }
}

export function applyAssetPreviewValue(
  rawValue: string,
  setPathValue: (next: string) => void,
  setAssetIdValue: (next: string) => void
): void {
  const trimmed = String(rawValue || '').trim()
  if (!trimmed) return

  if (/^\d+$/.test(trimmed)) {
    const parsedId = Number.parseInt(trimmed, 10)
    if (Number.isFinite(parsedId) && parsedId > 0) {
      setAssetIdValue(String(parsedId))
      setPathValue('')
      return
    }
  }

  setPathValue(trimmed)
}

export function splitMetadataTagList(raw?: string): string[] {
  return String(raw || '')
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean)
}

export function normalizeMetadataPluginTags(rawTags: string[]): string[] {
  return rawTags.map((tag) => tag.trim()).filter(Boolean)
}

export function parseMetadataAssetId(raw: string): number | undefined {
  const value = Number(raw.trim())
  if (!Number.isFinite(value)) return undefined
  const parsedId = Math.trunc(value)
  return parsedId > 0 ? parsedId : undefined
}

export function normalizeMetadataPluginChildren(rawChildren: unknown[]): TankoubonMemberMetadataPatch[] {
  return rawChildren
    .map((item) => normalizeTankoubonMemberMetadataPatch(item))
    .filter((item) => item.archive_id || item.volume_no)
}

export function parseMetadataPluginRpcSelectRequest(message: string): RpcSelectRequest | null {
  const prefix = '[RPC_SELECT]'
  if (!message?.startsWith(prefix)) return null

  try {
    const parsed = JSON.parse(message.slice(prefix.length)) as RpcSelectRequest
    if (!parsed?.request_id || !Array.isArray(parsed.options) || parsed.options.length === 0) {
      return null
    }
    return parsed
  } catch {
    return null
  }
}
