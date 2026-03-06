'use client';

import { useState, useEffect, useCallback, Suspense, useMemo, useRef } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/spinner';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Progress } from '@/components/ui/progress';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { ArchiveService } from '@/lib/services/archive-service';
import { ChunkedUploadService } from '@/lib/services/chunked-upload-service';
import { TaskPoolService } from '@/lib/services/taskpool-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { PluginService, type Plugin } from '@/lib/services/plugin-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useToast } from '@/hooks/use-toast';
import { logger } from '@/lib/utils/logger';
import { stripNamespace, parseTags } from '@/lib/utils/tag-utils';
import { getArchiveAssetId, getCoverAssetId } from '@/lib/utils/archive-assets';
import { ArchiveMetadataEditDialog } from '@/components/archive/ArchiveMetadataEditDialog';
import { ArrowLeft, Edit, Trash2, Plus, BookOpen, Heart, Search, MoreHorizontal, X, ExternalLink, LayoutGrid, List, Eye } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';
import Image from 'next/image';

type ArchiveViewMode = 'grid' | 'list';

type RpcSelectOption = {
  index: number;
  label: string;
  description?: string;
  cover?: string;
};

type RpcSelectRequest = {
  request_id: string;
  title: string;
  message?: string;
  default_index?: number;
  timeout_seconds?: number;
  options: RpcSelectOption[];
};

function parseRpcSelectRequest(message: string): RpcSelectRequest | null {
  const prefix = '[RPC_SELECT]';
  if (!message?.startsWith(prefix)) return null;
  try {
    const parsed = JSON.parse(message.slice(prefix.length)) as RpcSelectRequest;
    if (!parsed?.request_id || !Array.isArray(parsed?.options) || parsed.options.length === 0) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

const ARCHIVE_VIEW_MODE_STORAGE_KEY = 'tankoubon_archive_view_mode';
const MOBILE_BREAKPOINT_MEDIA_QUERY = '(max-width: 639px)';

type ArchiveListItemProps = {
  archive: Archive;
  isRemoving: boolean;
  onRemove: () => void;
};

function ArchiveListItem({ archive, isRemoving, onRemove }: ArchiveListItemProps) {
  const router = useRouter();
  const { t } = useLanguage();
  const coverAssetId = getArchiveAssetId(archive, 'cover');
  const [isFavorite, setIsFavorite] = useState(archive.isfavorite || false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const parsedTags = useMemo(() => parseTags(archive.tags).map(stripNamespace).slice(0, 8), [archive.tags]);

  useEffect(() => {
    setIsFavorite(archive.isfavorite || false);
  }, [archive.isfavorite]);

  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (favoriteLoading) return;
    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleFavorite(archive.arcid, isFavorite);
      if (success) setIsFavorite(!isFavorite);
    } catch (error) {
      logger.operationFailed('toggle archive favorite', error);
    } finally {
      setFavoriteLoading(false);
    }
  };

  const handleNavigateToReader = () => {
    router.push(`/reader?id=${archive.arcid}`);
  };

  return (
    <div
      className="relative rounded-lg border bg-card p-3 sm:p-4 cursor-pointer transition-shadow hover:shadow-sm"
      role="button"
      tabIndex={0}
      onClick={handleNavigateToReader}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          handleNavigateToReader();
        }
      }}
    >
      <div className="absolute right-3 top-3 flex items-center gap-2">
        <Button
          asChild
          variant="secondary"
          size="icon"
          className="h-8 w-8"
          title={t('archive.details')}
          onClick={(e) => e.stopPropagation()}
        >
          <Link href={`/archive?id=${archive.arcid}`} prefetch={false}>
            <Eye className="h-4 w-4" />
          </Link>
        </Button>
        <Button
          type="button"
          variant="secondary"
          size="icon"
          className={`h-8 w-8 ${isFavorite ? 'text-red-500' : ''}`}
          title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
          disabled={favoriteLoading}
          onClick={handleFavoriteClick}
        >
          {favoriteLoading ? <Spinner size="sm" /> : <Heart className={`h-4 w-4 ${isFavorite ? 'fill-current' : ''}`} />}
        </Button>
        <Button
          type="button"
          variant="secondary"
          size="icon"
          className="h-8 w-8"
          title={t('tankoubon.removeArchive')}
          disabled={isRemoving}
          onClick={(e) => {
            e.stopPropagation();
            onRemove();
          }}
        >
          {isRemoving ? <Spinner size="sm" /> : <Trash2 className="h-4 w-4" />}
        </Button>
      </div>

      <div className="flex gap-3 sm:gap-4">
        <div className="relative h-24 w-16 shrink-0 overflow-hidden rounded-md bg-muted">
          {coverAssetId ? (
            <Image
              src={`/api/assets/${coverAssetId}`}
              alt={archive.title}
              fill
              className="object-cover"
              sizes="96px"
              decoding="async"
            />
          ) : (
            <div className="absolute inset-0 flex items-center justify-center text-[10px] text-muted-foreground">
              {t('archive.noCover')}
            </div>
          )}
        </div>

        <div className="min-w-0 flex-1 pr-28">
          <h3 className="font-semibold leading-tight line-clamp-2 hover:text-primary transition-colors" title={archive.title}>
            {archive.title}
          </h3>
          <div className="mt-1 text-xs text-muted-foreground">
            {t('archive.pages').replace('{count}', String(archive.pagecount))}
            {archive.progress > 0 && archive.pagecount > 0
              ? ` • ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}`
              : ''}
          </div>

          {archive.summary && (
            <p className="mt-2 text-sm text-muted-foreground line-clamp-2" title={archive.summary}>
              {archive.summary}
            </p>
          )}

          {parsedTags.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1">
              {parsedTags.map((tag) => (
                <Badge key={`${archive.arcid}-${tag}`} variant="secondary" className="max-w-full text-[10px] sm:text-xs" title={tag}>
                  <span className="truncate">{tag}</span>
                </Badge>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function TankoubonDetailContent() {
  const { t, language } = useLanguage();
  const { success, error: showError } = useToast();
  const searchParams = useSearchParams();
  const router = useRouter();
  const tankoubonId = searchParams?.get('id') ?? null;

  const [tankoubon, setTankoubon] = useState<Tankoubon | null>(null);
  const [archives, setArchives] = useState<Archive[]>([]);
  const [loading, setLoading] = useState(true);
  const [archivesLoading, setArchivesLoading] = useState(false);
  const [isFavorite, setIsFavorite] = useState(false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [mobileActionsOpen, setMobileActionsOpen] = useState(false);

  // Edit dialog state
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editName, setEditName] = useState('');
  const [editSummary, setEditSummary] = useState('');
  const [editTags, setEditTags] = useState<string[]>([]);
  const [editCover, setEditCover] = useState('');
  const [editBackdrop, setEditBackdrop] = useState('');
  const [editClearlogo, setEditClearlogo] = useState('');
  const [editAssetCoverId, setEditAssetCoverId] = useState('');
  const [editAssetBackdropId, setEditAssetBackdropId] = useState('');
  const [editAssetClearlogoId, setEditAssetClearlogoId] = useState('');
  const [coverUploading, setCoverUploading] = useState(false);
  const [backdropUploading, setBackdropUploading] = useState(false);
  const [clearlogoUploading, setClearlogoUploading] = useState(false);
  const [saving, setSaving] = useState(false);

  // Metadata plugin state (preview mode: fill edit form without DB write-back)
  const [metadataPlugins, setMetadataPlugins] = useState<Plugin[]>([]);
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = useState<string>('');
  const [metadataPluginParam, setMetadataPluginParam] = useState<string>('');
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = useState(false);
  const [metadataPluginProgress, setMetadataPluginProgress] = useState<number | null>(null);
  const [metadataPluginMessage, setMetadataPluginMessage] = useState<string>('');
  const [rpcSelectTaskId, setRpcSelectTaskId] = useState<number | null>(null);
  const [rpcSelectRequest, setRpcSelectRequest] = useState<RpcSelectRequest | null>(null);
  const [rpcSelectSelectedIndex, setRpcSelectSelectedIndex] = useState<number | null>(null);
  const [rpcSelectRemainingSeconds, setRpcSelectRemainingSeconds] = useState<number | null>(null);
  const resolvedRpcSelectRequestIdsRef = useRef<Set<string>>(new Set());


  useEffect(() => {
    if (!rpcSelectRequest || rpcSelectRemainingSeconds == null) return;
    if (rpcSelectRemainingSeconds <= 0) {
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
      return;
    }

    const timer = window.setTimeout(() => {
      setRpcSelectRemainingSeconds((current) => {
        if (current == null) return null;
        return Math.max(0, current - 1);
      });
    }, 1000);

    return () => window.clearTimeout(timer);
  }, [rpcSelectRemainingSeconds, rpcSelectRequest]);
  const [metadataArchivePatches, setMetadataArchivePatches] = useState<Array<{
    archive_id?: string;
    volume_no?: number;
    title?: string;
    summary?: string;
    tags?: string;
    updated_at?: string;
    cover?: string;
    backdrop?: string;
    clearlogo?: string;
  }>>([]);

  // Delete dialog state
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  // Remove archive state
  const [removeDialogOpen, setRemoveDialogOpen] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<Archive | null>(null);
  const [removingArcids, setRemovingArcids] = useState<Set<string>>(new Set());

  // Add archive dialog state
  const [addArchiveDialogOpen, setAddArchiveDialogOpen] = useState(false);
  const [availableArchives, setAvailableArchives] = useState<Archive[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchLoading, setSearchLoading] = useState(false);
  const [selectedArchives, setSelectedArchives] = useState<Set<string>>(new Set());
  const [addingArchives, setAddingArchives] = useState(false);

  // Archive filter (within this collection)
  const [archiveFilter, setArchiveFilter] = useState('');
  const [archiveViewMode, setArchiveViewMode] = useState<ArchiveViewMode>('grid');

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const saved = window.localStorage.getItem(ARCHIVE_VIEW_MODE_STORAGE_KEY);
    if (saved === 'grid' || saved === 'list') {
      setArchiveViewMode(saved);
      return;
    }

    const mobileDefault = typeof window.matchMedia === 'function'
      ? window.matchMedia(MOBILE_BREAKPOINT_MEDIA_QUERY).matches
      : false;
    setArchiveViewMode(mobileDefault ? 'list' : 'grid');
  }, []);

  const handleArchiveViewModeChange = useCallback((mode: ArchiveViewMode) => {
    setArchiveViewMode(mode);
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(ARCHIVE_VIEW_MODE_STORAGE_KEY, mode);
    }
  }, []);

  // Fetch tankoubon details
  const fetchTankoubon = useCallback(async () => {
    if (!tankoubonId) return;

    try {
      setLoading(true);
      const data = await TankoubonService.getTankoubonById(tankoubonId);

      // Prefer translated tags coming from the search endpoint (avoids /api/tags/translations)
      try {
        const searchResult = await ArchiveService.search({
          tankoubon_id: tankoubonId,
          groupby_tanks: true,
          page: 1,
          pageSize: 1,
          sortby: 'tank_order',
          order: 'asc',
          lang: language,
        });
        const tankItem = searchResult.data.find(
          (item): item is Tankoubon => Boolean(item) && typeof item === 'object' && 'tankoubon_id' in item
        );
        if (tankItem && tankItem.tankoubon_id === tankoubonId && typeof tankItem.tags === 'string') {
          data.tags = tankItem.tags;
        }
      } catch {
        // Ignore; fall back to untranslated tags
      }

      setTankoubon(data);
      setIsFavorite(data.isfavorite || false);

      // Set edit form values
      setEditName(data.name);
      setEditSummary(data.summary || '');
      setEditTags(
        (data.tags || '')
          .split(',')
          .map((tag) => tag.trim())
          .filter((tag) => tag)
      );
      setEditCover('');
      setEditBackdrop('');
      setEditClearlogo('');
      setEditAssetCoverId(String(getCoverAssetId(data) || ''));
      setEditAssetBackdropId(String(data.assets?.backdrop || ''));
      setEditAssetClearlogoId(String(data.assets?.clearlogo || ''));
    } catch (error) {
      logger.apiError('fetch tankoubon', error);
    } finally {
      setLoading(false);
    }
  }, [tankoubonId, language]);

  // Fetch archives in tankoubon
  const fetchArchives = useCallback(async () => {
    if (!tankoubon?.tankoubon_id || !tankoubon?.archives || tankoubon.archives.length === 0) {
      setArchives([]);
      return;
    }

    try {
      setArchivesLoading(true);
      const result = await ArchiveService.search({
        tankoubon_id: tankoubon.tankoubon_id,
        sortby: 'tank_order',
        order: 'asc',
        page: 1,
        pageSize: 10000,
        groupby_tanks: false,
        lang: language,
      });
      const archiveItems = result.data.filter(
        (item): item is Archive => Boolean(item) && typeof item === 'object' && 'arcid' in item
      );
      setArchives(archiveItems || []);
    } catch (error) {
      logger.apiError('fetch archives', error);
    } finally {
      setArchivesLoading(false);
    }
  }, [tankoubon?.archives, tankoubon?.tankoubon_id, language]);

  useEffect(() => {
    fetchTankoubon();
  }, [fetchTankoubon]);

  useEffect(() => {
    if (tankoubon) {
      fetchArchives();
    }
  }, [tankoubon, fetchArchives]);

  // Helper function to display translated tag
  const displayTag = useCallback((tag: string): string => {
    const key = String(tag || '').trim();
    if (!key) return '';
    const idx = key.indexOf(':');
    return idx > 0 ? key.slice(idx + 1) : key;
  }, []);

  const handleTagClick = useCallback((tag: string) => {
    const canonical = String(tag || '').trim();
    if (!canonical) return;
    const q = canonical.includes(':') ? canonical : displayTag(canonical);
    const trimmed = q.trim();
    if (!trimmed) return;
    const exactQuery = trimmed.endsWith('$') ? trimmed : `${trimmed}$`;
    router.push(`/?q=${encodeURIComponent(exactQuery)}`);
  }, [displayTag, router]);

  const renderTagBadge = useCallback((tag: string, index: number) => {
    const key = String(tag || '').trim();
    const idx = key.indexOf(':');
    const namespace = idx > 0 ? key.slice(0, idx).trim().toLowerCase() : '';
    const isSource = namespace === 'source';
    const sourceValue = isSource ? displayTag(key).trim() : '';
    const hasScheme = sourceValue.startsWith('http://') || sourceValue.startsWith('https://');
    const sourceUrl = isSource && sourceValue ? (hasScheme ? sourceValue : `https://${sourceValue}`) : '';

    return (
      <Badge
        key={`${tag}-${index}`}
        variant="secondary"
        className="max-w-full cursor-pointer"
        title={tag}
        onClick={() => handleTagClick(tag)}
      >
        <span className="flex items-center gap-1 max-w-full">
          <span className="truncate">{displayTag(tag)}</span>
          {isSource && sourceValue && (
            <a
              href={sourceUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-primary transition-colors shrink-0"
              title={sourceUrl}
              onClick={(e) => e.stopPropagation()}
            >
              <ExternalLink className="w-3.5 h-3.5" />
            </a>
          )}
        </span>
      </Badge>
    );
  }, [displayTag, handleTagClick]);

  const handleFavoriteClick = async () => {
    if (!tankoubon || favoriteLoading) return;
    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleTankoubonFavorite(tankoubon.tankoubon_id, isFavorite);
      if (success) {
        setIsFavorite(!isFavorite);
        setTankoubon({ ...tankoubon, isfavorite: !isFavorite });
      }
    } catch (error) {
      logger.operationFailed('toggle tankoubon favorite', error);
    } finally {
      setFavoriteLoading(false);
    }
  };

  // Handle edit
  const handleEdit = async () => {
    if (!tankoubon) return;

    try {
      setSaving(true);
      const parseAssetId = (raw: string): number | undefined => {
        const value = Number(String(raw || '').trim());
        if (!Number.isFinite(value)) return undefined;
        const id = Math.trunc(value);
        return id > 0 ? id : undefined;
      };
      await TankoubonService.updateTankoubon(tankoubon.tankoubon_id, {
        name: editName,
        summary: editSummary,
        tags: editTags.join(', '),
        cover: editCover || undefined,
        backdrop: editBackdrop || undefined,
        clearlogo: editClearlogo || undefined,
        assets: {
          cover: parseAssetId(editAssetCoverId),
          backdrop: parseAssetId(editAssetBackdropId),
          clearlogo: parseAssetId(editAssetClearlogoId),
        },
        metadata_namespace: selectedMetadataPlugin || undefined,
        archives: metadataArchivePatches,
      });
      setEditDialogOpen(false);
      setMetadataArchivePatches([]);
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('update tankoubon', error);
    } finally {
      setSaving(false);
    }
  };

  const uploadMetadataAsset = useCallback((slot: 'cover' | 'backdrop' | 'clearlogo') => {
    if (saving || isMetadataPluginRunning) return;

    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.style.display = 'none';

    const setUploading = (next: boolean) => {
      if (slot === 'cover') {
        setCoverUploading(next);
        return;
      }
      if (slot === 'backdrop') {
        setBackdropUploading(next);
        return;
      }
      setClearlogoUploading(next);
    };

    input.onchange = async (event) => {
      const e = event as unknown as React.ChangeEvent<HTMLInputElement>;
      const file = e.target.files?.[0];
      if (!file) {
        document.body.removeChild(input);
        return;
      }

      setUploading(true);
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
        );
        if (!result.success) {
          throw new Error(result.error || t('archive.assetUploadFailed'));
        }

        const assetId = Number(result.data?.assetId ?? 0);
        if (!Number.isFinite(assetId) || assetId <= 0) {
          throw new Error(t('archive.assetUploadFailed'));
        }
        const normalizedAssetId = String(Math.trunc(assetId));

        if (slot === 'cover') {
          setEditAssetCoverId(normalizedAssetId);
          setEditCover('');
        } else if (slot === 'backdrop') {
          setEditAssetBackdropId(normalizedAssetId);
          setEditBackdrop('');
        } else {
          setEditAssetClearlogoId(normalizedAssetId);
          setEditClearlogo('');
        }

        success(t('archive.assetUploadSuccess'));
      } catch (error: any) {
        logger.operationFailed('upload tankoubon metadata asset', error, { slot });
        showError(error?.response?.data?.message || error?.message || t('archive.assetUploadFailed'));
      } finally {
        setUploading(false);
        document.body.removeChild(input);
      }
    };

    document.body.appendChild(input);
    input.click();
  }, [isMetadataPluginRunning, saving, showError, success, t]);

  // Load metadata plugins when opening the edit dialog
  useEffect(() => {
    if (!editDialogOpen) return;
    let cancelled = false;
    (async () => {
      try {
        const metas = await PluginService.getMetadataPlugins();
        if (cancelled) return;
        setMetadataPlugins(metas);
        if (!selectedMetadataPlugin && metas.length > 0) {
          setSelectedMetadataPlugin(metas[0].namespace);
        }
      } catch (e) {
        logger.apiError('load metadata plugins', e);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [editDialogOpen, selectedMetadataPlugin]);

  const submitRpcSelect = useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest || rpcSelectSelectedIndex == null) return;
    const requestId = rpcSelectRequest.request_id;
    const ok = await TaskPoolService.respondRpcSelect(rpcSelectTaskId, requestId, rpcSelectSelectedIndex);
    resolvedRpcSelectRequestIdsRef.current.add(requestId);
    if (!ok) {
      logger.operationFailed('respond metadata rpc select (tankoubon)', new Error('rpc select response failed'));
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
      return;
    }
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemainingSeconds(null);
  }, [rpcSelectRequest, rpcSelectSelectedIndex, rpcSelectTaskId]);

  const abortRpcSelect = useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest) return;
    const requestId = rpcSelectRequest.request_id;
    const ok = await TaskPoolService.abortRpcSelect(rpcSelectTaskId, requestId);
    resolvedRpcSelectRequestIdsRef.current.add(requestId);
    if (!ok) {
      logger.operationFailed('abort metadata rpc select (tankoubon)', new Error('rpc select abort failed'));
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
      return;
    }
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemainingSeconds(null);
  }, [rpcSelectRequest, rpcSelectTaskId]);

  const runMetadataPlugin = useCallback(async () => {
    if (!tankoubon) return;
    if (!selectedMetadataPlugin) return;

    resolvedRpcSelectRequestIdsRef.current.clear();
    setIsMetadataPluginRunning(true);
    setMetadataPluginProgress(0);
    setMetadataPluginMessage(t('archive.metadataPluginEnqueued'));
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemainingSeconds(null);

    try {
      const metadataTags = editTags.map((tag) => tag.trim()).filter(Boolean);
      const toAssetValue = (pathValue: string, assetId: string): string => {
        const path = pathValue.trim();
        if (path) return path;
        const id = assetId.trim();
        if (/^\d+$/.test(id)) return id;
        return '';
      };
      const rootAssets = [
        { key: 'cover', value: toAssetValue(editCover, editAssetCoverId) },
        { key: 'backdrop', value: toAssetValue(editBackdrop, editAssetBackdropId) },
        { key: 'clearlogo', value: toAssetValue(editClearlogo, editAssetClearlogoId) },
      ].filter((item) => item.value);
      const archiveMembers = metadataArchivePatches.map((item) => {
        const memberAssets = [
          { key: 'cover', value: String(item.cover || '').trim() },
          { key: 'backdrop', value: String(item.backdrop || '').trim() },
          { key: 'clearlogo', value: String(item.clearlogo || '').trim() },
        ].filter((asset) => asset.value);
        return {
          title: item.title || '',
          type: 0,
          description: item.summary || '',
          tags: String(item.tags || '')
            .split(',')
            .map((tag) => tag.trim())
            .filter(Boolean),
          assets: memberAssets,
          archive: [],
          archive_id: item.archive_id,
          volume_no: item.volume_no,
          updated_at: item.updated_at,
        };
      });
      const finalTask = await ArchiveService.runMetadataPluginForTarget(
        'tankoubon',
        tankoubon.tankoubon_id,
        selectedMetadataPlugin,
        metadataPluginParam,
        {
          onUpdate: (task) => {
            setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0);
            setMetadataPluginMessage(task.message || '');

            const req = parseRpcSelectRequest(task.message || '');
            if (req) {
              if (resolvedRpcSelectRequestIdsRef.current.has(req.request_id)) return;
              setRpcSelectTaskId(task.id);
              setRpcSelectRequest((current) => {
                if (current?.request_id === req.request_id) return current;
                const defaultIndex = typeof req.default_index === 'number' ? req.default_index : 0;
                setRpcSelectSelectedIndex(defaultIndex >= 0 && defaultIndex < req.options.length ? defaultIndex : 0);
                const timeout = typeof req.timeout_seconds === 'number' && req.timeout_seconds > 0 ? Math.floor(req.timeout_seconds) : 90;
                setRpcSelectRemainingSeconds(timeout);
                return req;
              });
            }
          },
        },
        {
          writeBack: false,
          metadata: {
            title: editName,
            type: 1,
            description: editSummary,
            tags: metadataTags,
            assets: rootAssets,
            archive: archiveMembers,
          },
        }
      );

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
        logger.operationFailed('run metadata plugin (tankoubon)', new Error(err));
        return;
      }

      // Preview mode: parse plugin output and fill the edit form (no DB write-back).
      try {
        const out = finalTask.result ? JSON.parse(finalTask.result) : null;
        const ok = out?.success === true || out?.success === 1 || out?.success === '1' || out?.success === 'true';
        if (!ok) {
          const err = out?.error || finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
          logger.operationFailed('run metadata plugin (tankoubon)', new Error(err));
          return;
        }

        const data = out?.data || {};
        const readAssetValue = (assets: unknown, key: string): string => {
          if (!Array.isArray(assets)) return '';
          for (const item of assets) {
            if (!item || typeof item !== 'object') continue;
            const row = item as Record<string, unknown>;
            const itemKey = String(row.key ?? row.type ?? row.name ?? '').trim().toLowerCase();
            if (itemKey !== key) continue;
            const value = row.value;
            if (typeof value === 'string') return value.trim();
            if (typeof value === 'number' && Number.isFinite(value)) return String(Math.trunc(value));
            return '';
          }
          return '';
        };
        const nextTitle = typeof data.title === 'string' ? data.title : '';
        const nextSummary = typeof data.description === 'string' ? data.description : '';
        const nextTags = Array.isArray(data.tags)
          ? data.tags.map((tag: unknown) => String(tag || '').trim()).filter(Boolean)
          : [];
        const nextCover = readAssetValue(data.assets, 'cover');
        const nextBackdrop = readAssetValue(data.assets, 'backdrop');
        const nextClearlogo = readAssetValue(data.assets, 'clearlogo');
        const nextArchives = Array.isArray(data.archive) ? data.archive : [];
        const applyAssetPreview = (
          rawValue: string,
          setPathValue: (next: string) => void,
          setAssetIdValue: (next: string) => void
        ) => {
          const trimmed = rawValue.trim();
          if (!trimmed) return;
          if (/^\d+$/.test(trimmed)) {
            const id = Number.parseInt(trimmed, 10);
            if (Number.isFinite(id) && id > 0) {
              setAssetIdValue(String(id));
              setPathValue('');
              return;
            }
          }
          setPathValue(trimmed);
        };

        if (nextTitle.trim()) setEditName(nextTitle);
        setEditSummary(nextSummary);
        setEditTags(nextTags);
        applyAssetPreview(nextCover, setEditCover, setEditAssetCoverId);
        applyAssetPreview(nextBackdrop, setEditBackdrop, setEditAssetBackdropId);
        applyAssetPreview(nextClearlogo, setEditClearlogo, setEditAssetClearlogoId);

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
              backdrop: readAssetValue(item?.assets, 'backdrop') || undefined,
              clearlogo: readAssetValue(item?.assets, 'clearlogo') || undefined,
            }))
            .filter((item: any) => item.archive_id || item.volume_no)
        );
      } catch {
        // ignore parse errors
      }

      setMetadataPluginMessage(t('archive.metadataPluginCompleted'));
      setMetadataPluginProgress(100);
    } catch (e) {
      logger.operationFailed('run metadata plugin (tankoubon)', e);
    } finally {
      setIsMetadataPluginRunning(false);
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
    }
  }, [
    editName,
    editSummary,
    editTags,
    editCover,
    editBackdrop,
    editClearlogo,
    editAssetCoverId,
    editAssetBackdropId,
    editAssetClearlogoId,
    metadataArchivePatches,
    tankoubon,
    selectedMetadataPlugin,
    metadataPluginParam,
    t,
  ]);

  // Handle delete
  const handleDelete = async () => {
    if (!tankoubon) return;

    try {
      setDeleting(true);
      await TankoubonService.deleteTankoubon(tankoubon.tankoubon_id);
      router.push('/');
    } catch (error) {
      logger.operationFailed('delete tankoubon', error);
      setDeleting(false);
    }
  };

  // Handle remove archive from tankoubon
  const handleRemoveArchive = async (arcid: string) => {
    if (!tankoubon) return;

    try {
      setRemovingArcids((prev) => new Set(prev).add(arcid));
      await TankoubonService.removeArchiveFromTankoubon(tankoubon.tankoubon_id, arcid);
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('remove archive', error);
    } finally {
      setRemovingArcids((prev) => {
        const next = new Set(prev);
        next.delete(arcid);
        return next;
      });
    }
  };

  const confirmRemoveArchive = async () => {
    if (!removeTarget) return;
    await handleRemoveArchive(removeTarget.arcid);
    setRemoveDialogOpen(false);
    setRemoveTarget(null);
  };

  // Search for archives to add
  const searchArchives = async () => {
    try {
      setSearchLoading(true);
      const result = await ArchiveService.search({
        filter: searchQuery,
        page: 1,
        pageSize: 50,
        groupby_tanks: false, // Don't group by tanks when searching for archives to add
        lang: language,
      });

      // Filter out archives already in this tankoubon
      const existingArcids = new Set(tankoubon?.archives || []);
      const filtered = result.data
        .filter((item): item is Archive => Boolean(item) && typeof item === 'object' && 'arcid' in item)
        .filter((a) => !existingArcids.has(a.arcid));
      setAvailableArchives(filtered);
    } catch (error) {
      logger.apiError('search archives', error);
    } finally {
      setSearchLoading(false);
    }
  };

  // Handle add archives
  const handleAddArchives = async () => {
    if (!tankoubon || selectedArchives.size === 0) return;

    try {
      setAddingArchives(true);
      const promises = Array.from(selectedArchives).map((arcid) =>
        TankoubonService.addArchiveToTankoubon(tankoubon.tankoubon_id, arcid)
      );
      await Promise.all(promises);
      setAddArchiveDialogOpen(false);
      setSelectedArchives(new Set());
      setAvailableArchives([]);
      setSearchQuery('');
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('add archives', error);
    } finally {
      setAddingArchives(false);
    }
  };

  // Toggle archive selection
  const toggleArchiveSelection = (arcid: string) => {
    const newSelected = new Set(selectedArchives);
    if (newSelected.has(arcid)) {
      newSelected.delete(arcid);
    } else {
      newSelected.add(arcid);
    }
    setSelectedArchives(newSelected);
  };

  const filteredArchives = useMemo(() => {
    const q = archiveFilter.trim().toLowerCase();
    if (!q) return archives;
    return archives.filter((a) => {
      const title = String(a.title || '').toLowerCase();
      const tags = String(a.tags || '').toLowerCase();
      return title.includes(q) || tags.includes(q);
    });
  }, [archives, archiveFilter]);

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <main className="container mx-auto px-4 py-8">
          <div className="flex justify-center items-center h-64">
            <Spinner size="lg" />
          </div>
        </main>
      </div>
    );
  }

  if (!tankoubon) {
    return (
      <div className="min-h-screen bg-background">
        <main className="container mx-auto px-4 py-8">
          <div className="text-center py-12">
            <p className="text-muted-foreground">{t('tankoubon.notFound')}</p>
            <Button onClick={() => router.push('/')} className="mt-4">
              <ArrowLeft className="w-4 h-4 mr-2" />
              {t('common.back')}
            </Button>
          </div>
        </main>
      </div>
    );
  }

  const allTags = tankoubon.tags
    ? tankoubon.tags.split(',').map((tag) => tag.trim()).filter((tag) => tag)
    : [];

  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : archives.length;
  const totalPages = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const totalProgress = typeof tankoubon.progress === 'number' ? tankoubon.progress : 0;
  const progressPercent =
    totalPages > 0 && totalProgress > 0
      ? Math.max(0, Math.min(100, Math.round((totalProgress / totalPages) * 100)))
      : 0;
  const coverAssetId = getCoverAssetId(tankoubon) ?? 0;
  const coverUrl = coverAssetId > 0
    ? `/api/assets/${coverAssetId}`
    : '';

  return (
    <div className="min-h-dvh bg-background pb-20 lg:pb-0">
      <main className="container mx-auto px-4 pt-6 pb-4 sm:pb-6 max-w-7xl">
        {/* Header / hero */}
        <div className="relative mb-8">
          <div className="relative rounded-2xl border bg-card/70 backdrop-blur">
            <div className="p-4 md:p-5">
              {/* Mobile: keep hero clean; actions live in a bottom sheet. */}
              <div className="sm:hidden absolute right-4 top-4">
                <Button
                  variant="outline"
                  size="sm"
                  className="h-9 w-9 p-0"
                  aria-label={t('common.actions')}
                  onClick={() => setMobileActionsOpen(true)}
                >
                  <MoreHorizontal className="w-4 h-4" />
                </Button>
              </div>

              <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                <div className="flex min-w-0 gap-4">
                  <div className="relative h-44 w-32 shrink-0 overflow-hidden rounded-xl border bg-muted sm:h-48 sm:w-36 md:h-56 md:w-40 lg:h-60 lg:w-44">
                    {coverUrl ? (
                      <Image
                        src={coverUrl}
                        alt={tankoubon.name}
                        fill
                        className="object-cover"
                        sizes="(max-width: 640px) 128px, (max-width: 768px) 144px, (max-width: 1024px) 160px, 176px"
                        unoptimized
                      />
                    ) : (
                      <div className="absolute inset-0 flex items-center justify-center text-xs text-muted-foreground">
                        {t('archive.noCover')}
                      </div>
                    )}
                  </div>

                  <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-3">
                    <Badge className="bg-primary">
                      <BookOpen className="w-3 h-3 mr-1" />
                      {t('tankoubon.collection')}
                    </Badge>
                    <h1 className="text-lg sm:text-xl md:text-2xl font-bold tracking-tight break-words">
                      {tankoubon.name}
                    </h1>
                  </div>

                  {/* Keep stats directly under title on all screen sizes (same as mobile). */}
                  <div className="mt-2">
                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                      <span className="tabular-nums">
                        {t('tankoubon.archiveCount')} {archiveCount}
                      </span>
                      <span className="text-muted-foreground/60">•</span>
                      <span className="tabular-nums">
                        {t('tankoubon.totalPagesLabel')} {totalPages}
                      </span>
                      <span className="text-muted-foreground/60">•</span>
                      <span className="tabular-nums">
                        {t('tankoubon.progress')} {progressPercent}%
                      </span>
                    </div>
                    {progressPercent > 0 ? (
                      <Progress className="mt-2 h-1.5" value={progressPercent} />
                    ) : null}
                  </div>

                  {/* Desktop/tablet: show summary/tags in the right column; mobile shows them full width below. */}
                  <div className="hidden sm:block">
                    {tankoubon.summary ? (
                      <p className="mt-2 text-sm text-muted-foreground max-w-3xl line-clamp-2">
                        {tankoubon.summary}
                      </p>
                    ) : null}

                    {allTags.length > 0 ? (
                      <div className="mt-3 flex flex-wrap gap-2">
                        {allTags.map((tag, index) => renderTagBadge(tag, index))}
                      </div>
                    ) : null}
                  </div>
                  </div>
                </div>

                {/* Desktop/tablet actions; mobile actions are in the sheet. */}
                <div className="hidden sm:flex shrink-0 flex-wrap items-center gap-2">
                  <Button
                    size="sm"
                    variant="outline"
                    className={`h-9 w-9 p-0 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
                    title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                    disabled={favoriteLoading}
                    onClick={handleFavoriteClick}
                  >
                    <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-9 w-9 p-0"
                    title={t('common.edit')}
                    onClick={() => setEditDialogOpen(true)}
                  >
                    <Edit className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-9 w-9 p-0 text-destructive"
                    title={t('common.delete')}
                    onClick={() => setDeleteDialogOpen(true)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
                </div>

              {/* Mobile: summary/tags span full width (avoid an empty left column under the cover). */}
              <div className="sm:hidden w-full">
                {tankoubon.summary ? (
                  <p className="text-sm text-muted-foreground max-w-3xl line-clamp-2">
                    {tankoubon.summary}
                  </p>
                ) : null}

                {allTags.length > 0 ? (
                  <div className="mt-3 flex flex-wrap gap-2 w-full">
                    {allTags.map((tag, index) => renderTagBadge(tag, index))}
                  </div>
                ) : null}
              </div>


            </div>
          </div>
        </div>

        <Sheet open={mobileActionsOpen} onOpenChange={setMobileActionsOpen}>
          <SheetContent
            side="bottom"
            className="px-4 pt-3 pb-[calc(env(safe-area-inset-bottom)+1rem)] max-h-[85vh] overflow-y-auto rounded-t-xl sm:hidden"
          >
            <div className="mx-auto mb-3 h-1.5 w-12 rounded-full bg-muted" />
            <SheetHeader className="mb-3">
              <SheetTitle>{t('common.actions')}</SheetTitle>
              <div className="text-sm text-muted-foreground line-clamp-2">{tankoubon.name}</div>
            </SheetHeader>

            <div className="space-y-2">
              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => {
                  setAddArchiveDialogOpen(true);
                  setMobileActionsOpen(false);
                }}
              >
                <Plus className="w-4 h-4 mr-2" />
                {t('tankoubon.addArchive')}
              </Button>

              <Button
                variant="outline"
                className={`w-full justify-start ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
                onClick={async () => {
                  await handleFavoriteClick();
                  setMobileActionsOpen(false);
                }}
                disabled={favoriteLoading}
              >
                <Heart className={`w-4 h-4 mr-2 ${isFavorite ? 'fill-current' : ''}`} />
                {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
              </Button>

              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => {
                  setEditDialogOpen(true);
                  setMobileActionsOpen(false);
                }}
              >
                <Edit className="w-4 h-4 mr-2" />
                {t('common.edit')}
              </Button>

              <Button
                variant="destructive"
                className="w-full justify-start"
                onClick={() => {
                  setDeleteDialogOpen(true);
                  setMobileActionsOpen(false);
                }}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                {t('common.delete')}
              </Button>

              <Button variant="outline" className="w-full justify-start" onClick={() => setMobileActionsOpen(false)}>
                <X className="w-4 h-4 mr-2" />
                {t('common.close')}
              </Button>
            </div>
          </SheetContent>
        </Sheet>

        {/* Archives section */}
        <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-semibold">{t('tankoubon.archivesTitle')}</h2>
            <Badge variant="secondary" className="tabular-nums">
              {archiveFilter.trim() ? `${filteredArchives.length}/${archives.length}` : String(archives.length)}
            </Badge>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-8 px-2 border-0 shadow-none"
              onClick={() => handleArchiveViewModeChange(archiveViewMode === 'grid' ? 'list' : 'grid')}
              title={archiveViewMode === 'grid' ? t('tankoubon.switchToListView') : t('tankoubon.switchToGridView')}
              aria-label={archiveViewMode === 'grid' ? t('tankoubon.switchToListView') : t('tankoubon.switchToGridView')}
            >
              {archiveViewMode === 'grid' ? <List className="h-4 w-4" /> : <LayoutGrid className="h-4 w-4" />}
              <span className="hidden sm:inline">
                {archiveViewMode === 'grid' ? t('tankoubon.listView') : t('tankoubon.gridView')}
              </span>
            </Button>
          </div>

          <div className="flex w-full gap-2 sm:w-auto">
            <div className="relative flex-1 sm:w-72">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={archiveFilter}
                onChange={(e) => setArchiveFilter(e.target.value)}
                placeholder={t('tankoubon.filterPlaceholder')}
                className="pl-9"
              />
            </div>
            <Button onClick={() => setAddArchiveDialogOpen(true)} className="shrink-0">
              <Plus className="w-4 h-4 mr-2" />
              {t('tankoubon.addArchive')}
            </Button>
          </div>
        </div>

        {archivesLoading ? (
          <div className="flex justify-center items-center h-32">
            <Spinner />
          </div>
        ) : archives.length === 0 ? (
          <div className="text-center py-12 bg-muted/50 rounded-lg">
            <p className="text-muted-foreground mb-4">{t('tankoubon.noArchives')}</p>
            <Button onClick={() => setAddArchiveDialogOpen(true)}>
              <Plus className="w-4 h-4 mr-2" />
              {t('tankoubon.addArchive')}
            </Button>
          </div>
        ) : filteredArchives.length === 0 ? (
          <div className="text-center py-12 bg-muted/30 rounded-lg border">
            <p className="text-muted-foreground mb-1">{t('tankoubon.noMatchingArchives')}</p>
            <Button variant="ghost" onClick={() => setArchiveFilter('')}>
              {t('common.reset')}
            </Button>
          </div>
        ) : archiveViewMode === 'grid' ? (
          <div className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
              {filteredArchives.map((archive, index) => {
                const isRemoving = removingArcids.has(archive.arcid);
                return (
                  <div key={archive.arcid} className="relative group">
                    <ArchiveCard archive={archive} index={index} />
                    <Button
                      type="button"
                      variant="secondary"
                      size="icon"
                      className="absolute right-2 top-2 h-8 w-8 rounded-full opacity-0 shadow-sm transition-opacity group-hover:opacity-100 focus:opacity-100"
                      title={t('tankoubon.removeArchive')}
                      disabled={isRemoving}
                      onClick={() => {
                        setRemoveTarget(archive);
                        setRemoveDialogOpen(true);
                      }}
                    >
                      {isRemoving ? <Spinner size="sm" /> : <Trash2 className="h-4 w-4" />}
                    </Button>
                  </div>
                );
              })}
            </div>
          </div>
        ) : (
          <div className="space-y-3 h-full flex flex-col">
            {filteredArchives.map((archive) => {
              const isRemoving = removingArcids.has(archive.arcid);
              return (
                <ArchiveListItem
                  key={archive.arcid}
                  archive={archive}
                  isRemoving={isRemoving}
                  onRemove={() => {
                    setRemoveTarget(archive);
                    setRemoveDialogOpen(true);
                  }}
                />
              );
            })}
          </div>
        )}

        <ConfirmDialog
          open={removeDialogOpen}
          onOpenChange={(open) => {
            setRemoveDialogOpen(open);
            if (!open) setRemoveTarget(null);
          }}
          title={t('tankoubon.removeArchiveConfirmTitle')}
          description={t('tankoubon.removeArchiveConfirmMessage').replace('{title}', removeTarget?.title ?? '')}
          onConfirm={confirmRemoveArchive}
          confirmText={t('common.remove')}
          cancelText={t('common.cancel')}
          variant="destructive"
        />

        <ArchiveMetadataEditDialog
          open={editDialogOpen}
          onOpenChange={setEditDialogOpen}
          t={t}
          titleLabel={t('tankoubon.name')}
          summaryLabel={t('tankoubon.summary')}
          tagsLabel={t('tankoubon.tags')}
          summaryPlaceholder={t('tankoubon.summaryPlaceholder')}
          tagsPlaceholder={t('tankoubon.tagsPlaceholder')}
          title={editName}
          onTitleChange={setEditName}
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
          isSaving={saving}
          saveDisabled={!editName.trim()}
          onSave={handleEdit}
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

        {/* Delete Confirmation Dialog */}
        <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>{t('tankoubon.deleteConfirmTitle')}</AlertDialogTitle>
              <AlertDialogDescription>
                {t('tankoubon.deleteConfirmMessage')}
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>{t('common.cancel')}</AlertDialogCancel>
              <AlertDialogAction
                onClick={handleDelete}
                className="bg-destructive text-destructive-foreground"
                disabled={deleting}
              >
                {deleting ? <Spinner size="sm" className="mr-2" /> : null}
                {t('common.delete')}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>

        {/* Add Archive Dialog */}
        <Dialog open={addArchiveDialogOpen} onOpenChange={setAddArchiveDialogOpen}>
          <DialogContent className="max-w-3xl max-h-[80vh]">
            <DialogHeader>
              <DialogTitle>{t('tankoubon.addArchive')}</DialogTitle>
            </DialogHeader>
            <DialogBody className="pt-0 space-y-4">
              <div className="flex gap-2">
                <Input
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder={t('tankoubon.searchArchivesPlaceholder')}
                  onKeyDown={(e) => e.key === 'Enter' && searchArchives()}
                />
                <Button onClick={searchArchives} disabled={searchLoading}>
                  {searchLoading ? <Spinner size="sm" /> : t('common.search')}
                </Button>
              </div>

              {availableArchives.length > 0 && (
                <div className="border rounded-lg p-4">
                  <p className="text-sm text-muted-foreground mb-3">
                    {t('tankoubon.selectArchives')} ({selectedArchives.size} {t('common.selected')})
                  </p>
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 max-h-96 overflow-y-auto">
                    {availableArchives.map((archive) => (
                      <div
                        key={archive.arcid}
                        className={`p-3 border rounded-lg cursor-pointer transition-colors ${
                          selectedArchives.has(archive.arcid)
                            ? 'border-primary bg-primary/10'
                            : 'hover:border-muted-foreground'
                        }`}
                        onClick={() => toggleArchiveSelection(archive.arcid)}
                      >
                        <p className="text-sm font-medium line-clamp-2">{archive.title}</p>
                        <p className="text-xs text-muted-foreground mt-1">
                          {archive.pagecount} {t('archive.pages').replace('{count}', '')}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {availableArchives.length === 0 && searchQuery && !searchLoading && (
                <p className="text-center text-muted-foreground py-8">{t('tankoubon.noArchivesFound')}</p>
              )}
            </DialogBody>
            <DialogFooter>
              <Button variant="outline" onClick={() => setAddArchiveDialogOpen(false)}>
                {t('common.cancel')}
              </Button>
              <Button
                onClick={handleAddArchives}
                disabled={addingArchives || selectedArchives.size === 0}
              >
                {addingArchives ? <Spinner size="sm" className="mr-2" /> : null}
                {t('tankoubon.addSelected')} ({selectedArchives.size})
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </main>

      <MobileBottomNav />
    </div>
  );
}

export default function TankoubonDetailPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-background pb-20 lg:pb-0">
        <main className="container mx-auto px-4 py-8">
          <div className="flex items-center justify-center py-12">
            <Spinner size="lg" />
          </div>
        </main>
        <MobileBottomNav />
      </div>
    }>
      <TankoubonDetailContent />
    </Suspense>
  );
}
