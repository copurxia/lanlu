'use client';

import Link from 'next/link';
import { BookOpen, CheckCircle, Download, Edit, ExternalLink, Heart, Play, RotateCcw, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { AddToTankoubonDialog } from '@/components/tankoubon/AddToTankoubonDialog';
import type { ArchiveMetadata } from '@/types/archive';
import type { Plugin } from '@/lib/plugin-service';
import { ArchiveService } from '@/lib/archive-service';
import { formatDate } from '../utils/format';
import { displayTag } from '../utils/tag';

type FormData = {
  title: string;
  summary: string;
  tags: string[];
};

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
  tags: string[];
  isEditing: boolean;
  isSaving: boolean;
  formData: FormData;
  setFormData: (next: FormData | ((prev: FormData) => FormData)) => void;
  isAuthenticated: boolean;
  isAdmin: boolean;
  isFavorite: boolean;
  favoriteLoading: boolean;
  isNewStatusLoading: boolean;
  deleteLoading: boolean;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onSaveEdit: () => Promise<void> | void;
  onFavoriteClick: () => Promise<void> | void;
  onMarkAsRead: () => Promise<void> | void;
  onMarkAsNew: () => Promise<void> | void;
  onDeleteArchive: () => Promise<void> | void;
  onTagClick: (fullTag: string) => void;
  metadataPlugins: Plugin[];
  selectedMetadataPlugin: string;
  setSelectedMetadataPlugin: (next: string) => void;
  metadataPluginParam: string;
  setMetadataPluginParam: (next: string) => void;
  isMetadataPluginRunning: boolean;
  metadataPluginProgress: number | null;
  metadataPluginMessage: string;
  onRunMetadataPlugin: () => Promise<void> | void;
};

export function ArchiveMainCard({
  metadata,
  t,
  tags,
  isEditing,
  isSaving,
  formData,
  setFormData,
  isAuthenticated,
  isAdmin,
  isFavorite,
  favoriteLoading,
  isNewStatusLoading,
  deleteLoading,
  onStartEdit,
  onCancelEdit,
  onSaveEdit,
  onFavoriteClick,
  onMarkAsRead,
  onMarkAsNew,
  onDeleteArchive,
  onTagClick,
  metadataPlugins,
  selectedMetadataPlugin,
  setSelectedMetadataPlugin,
  metadataPluginParam,
  setMetadataPluginParam,
  isMetadataPluginRunning,
  metadataPluginProgress,
  metadataPluginMessage,
  onRunMetadataPlugin,
}: Props) {
  return (
    <Card className="h-full flex flex-col">
      <CardHeader className="pb-3">
        {isEditing ? (
          <div className="space-y-3">
            <Input
              value={formData.title}
              onChange={(e) => setFormData((prev) => ({ ...prev, title: e.target.value }))}
              disabled={isSaving}
            />
            <Textarea
              value={formData.summary}
              onChange={(e) => setFormData((prev) => ({ ...prev, summary: e.target.value }))}
              disabled={isSaving}
              placeholder={t('archive.summaryPlaceholder')}
              className="min-h-[84px]"
            />

            <div className="pt-1">
              <div className="flex flex-col sm:flex-row gap-2">
                <div className="sm:w-[220px]">
                  <Select value={selectedMetadataPlugin} onValueChange={setSelectedMetadataPlugin}>
                    <SelectTrigger disabled={isSaving || isMetadataPluginRunning || metadataPlugins.length === 0}>
                      <SelectValue placeholder={t('archive.metadataPluginSelectPlaceholder')} />
                    </SelectTrigger>
                    <SelectContent>
                      {metadataPlugins.map((p) => (
                        <SelectItem key={p.namespace} value={p.namespace}>
                          {p.name} ({p.namespace})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <Input
                  value={metadataPluginParam}
                  onChange={(e) => setMetadataPluginParam(e.target.value)}
                  disabled={isSaving || isMetadataPluginRunning}
                  placeholder={t('archive.metadataPluginParamPlaceholder')}
                />
                <Button
                  type="button"
                  onClick={onRunMetadataPlugin}
                  disabled={
                    isSaving || isMetadataPluginRunning || metadataPlugins.length === 0 || !selectedMetadataPlugin
                  }
                >
                  <Play className="w-4 h-4 mr-2" />
                  {isMetadataPluginRunning ? t('archive.metadataPluginRunning') : t('archive.metadataPluginRun')}
                </Button>
              </div>
              {(metadataPluginProgress !== null || metadataPluginMessage) && (
                <div className="mt-2 text-xs text-muted-foreground flex items-center justify-between gap-2">
                  <span className="truncate" title={metadataPluginMessage}>
                    {metadataPluginMessage || ''}
                  </span>
                  {metadataPluginProgress !== null && (
                    <span className="tabular-nums">{Math.max(0, Math.min(100, metadataPluginProgress))}%</span>
                  )}
                </div>
              )}
              {metadataPlugins.length === 0 && (
                <div className="mt-2 text-xs text-muted-foreground">{t('archive.metadataPluginNoPlugins')}</div>
              )}
            </div>
          </div>
        ) : (
          <>
            <div className="flex items-start justify-between gap-3">
              <CardTitle className="text-lg lg:text-2xl leading-tight">{metadata.title}</CardTitle>
            </div>
            <p
              className={`mt-2 text-sm leading-relaxed ${
                metadata.summary ? 'text-muted-foreground' : 'text-muted-foreground italic'
              }`}
            >
              {metadata.summary || t('archive.noSummary')}
            </p>
          </>
        )}
      </CardHeader>

      <CardContent className="pt-0 flex flex-col gap-3 flex-1 min-h-0">
        {!isEditing && (
          <div className="rounded-md border border-border p-3">
            <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
              <div className="flex items-center justify-between gap-3">
                <span className="text-muted-foreground">{t('archive.pageCount')}</span>
                <span>{metadata.pagecount}</span>
              </div>
              <div className="flex items-center justify-between gap-3">
                <span className="text-muted-foreground">{t('archive.updatedAt')}</span>
                <span className="truncate">{formatDate(metadata.updated_at, t('archive.unknown'))}</span>
              </div>
            </div>
          </div>
        )}

        <div className="rounded-md border border-border p-3 flex-1 min-h-0 overflow-auto">
          {isEditing ? (
            <TagInput
              value={formData.tags}
              onChange={(newTags) => setFormData((prev) => ({ ...prev, tags: newTags }))}
              disabled={isSaving}
              placeholder={t('archive.tagsPlaceholder')}
              className="h-full min-h-0 border-0 bg-transparent px-0 py-0 ring-0 focus-within:ring-0 focus-within:ring-offset-0 rounded-none items-start content-start"
            />
          ) : tags.length > 0 ? (
            <div className="flex flex-wrap gap-2">
              {tags.map((fullTag) => {
                const label = displayTag(fullTag);
                const colonIdx = fullTag.indexOf(':');
                const namespace = colonIdx > 0 ? fullTag.slice(0, colonIdx).trim().toLowerCase() : '';
                const isSource = namespace === 'source';
                const sourceUrl = isSource ? (label.startsWith('http') ? label : `https://${label}`) : '';

                return (
                  <Badge
                    key={fullTag}
                    variant="secondary"
                    className="px-2.5 py-1 text-sm cursor-pointer select-none transition-colors hover:bg-secondary/80 flex items-center gap-1"
                    title={fullTag}
                    onClick={() => onTagClick(fullTag)}
                  >
                    <span>{label}</span>
                    {isSource && sourceUrl && (
                      <a
                        href={sourceUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="hover:text-primary transition-colors"
                        title={sourceUrl}
                        onClick={(e) => e.stopPropagation()}
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    )}
                  </Badge>
                );
              })}
            </div>
          ) : (
            <div className="h-full flex items-center justify-center text-muted-foreground text-sm italic">
              {t('archive.noTags')}
            </div>
          )}
        </div>

        <div className={`grid ${isEditing ? 'grid-cols-1 sm:grid-cols-2' : 'hidden sm:grid sm:grid-cols-2'} gap-2`}>
          {isEditing ? (
            <>
              <Button className="w-full" onClick={onSaveEdit} disabled={isSaving}>
                {isSaving ? t('common.saving') : t('common.save')}
              </Button>
              <Button variant="outline" className="w-full" onClick={onCancelEdit} disabled={isSaving}>
                {t('common.cancel')}
              </Button>
            </>
          ) : (
            <>
              <Link href={`/reader?id=${metadata.arcid}`} className="w-full">
                <Button className="w-full">
                  <BookOpen className="w-4 h-4 mr-2" />
                  {t('archive.startReading')}
                </Button>
              </Link>

              <Button
                variant="outline"
                className="w-full"
                onClick={() => {
                  const downloadUrl = ArchiveService.getDownloadUrl(metadata.arcid);
                  window.open(downloadUrl, '_blank');
                }}
              >
                <Download className="w-4 h-4 mr-2" />
                {t('archive.download')}
              </Button>

              <Button
                variant="outline"
                className={`w-full ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
                onClick={onFavoriteClick}
                disabled={favoriteLoading}
              >
                <Heart className={`w-4 h-4 mr-2 ${isFavorite ? 'fill-current' : ''}`} />
                {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
              </Button>

              {metadata.isnew ? (
                <Button variant="outline" className="w-full" onClick={onMarkAsRead} disabled={isNewStatusLoading}>
                  <CheckCircle className="w-4 h-4 mr-2" />
                  {isNewStatusLoading ? t('common.loading') : t('archive.markAsRead')}
                </Button>
              ) : (
                <Button variant="outline" className="w-full" onClick={onMarkAsNew} disabled={isNewStatusLoading}>
                  <RotateCcw className="w-4 h-4 mr-2" />
                  {isNewStatusLoading ? t('common.loading') : t('archive.markAsNew')}
                </Button>
              )}

              <AddToTankoubonDialog archiveId={metadata.arcid} fullWidth onAdded={() => {}} />

              {isAuthenticated ? (
                <Button variant="outline" className="w-full" onClick={onStartEdit}>
                  <Edit className="w-4 h-4 mr-2" />
                  {t('common.edit')}
                </Button>
              ) : (
                <Button variant="outline" className="w-full" disabled title="需要登录才能编辑">
                  <Edit className="w-4 h-4 mr-2" />
                  {t('common.edit')}
                </Button>
              )}

              {isAdmin && (
                <Button
                  variant="destructive"
                  className="w-full"
                  onClick={onDeleteArchive}
                  disabled={deleteLoading}
                >
                  <Trash2 className="w-4 h-4 mr-2" />
                  {deleteLoading ? t('common.loading') : t('common.delete')}
                </Button>
              )}
            </>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
