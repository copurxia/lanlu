"use client"

import * as React from 'react'
import Image from 'next/image'
import { useRouter } from 'next/navigation'
import { Check, Eye, Heart, Square } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { BaseMediaCardEditController } from '@/components/ui/base-media-card-edit-controller'
import { MediaCardActions } from '@/components/ui/media-card-actions'
import type { BaseMediaCardProps } from '@/components/ui/base-media-card.types'
import { useLanguage } from '@/contexts/LanguageContext'
import { useBaseMediaCardController } from '@/hooks/use-base-media-card-controller'
import { useRecommendationTracker } from '@/hooks/use-recommendation-tracker'
import { ArchiveService } from '@/lib/services/archive-service'
import { buildReaderPath } from '@/lib/utils/reader'
import { cn } from '@/lib/utils/utils'
import { parseTags, stripNamespace } from '@/lib/utils/tag-utils'

export type { BaseMediaCardProps } from '@/components/ui/base-media-card.types'

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
  surfaceClassName,
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
  const imageSrc =
    thumbnailUrl && thumbnailUrl.trim().length > 0
      ? thumbnailUrl
      : ArchiveService.getAssetUrl(thumbnailAssetId)
  const hasImage = imageSrc.trim().length > 0

  const router = useRouter()
  const { t } = useLanguage()
  const { trackOpenDetails, trackOpenReader, trackFavorite } = useRecommendationTracker({
    id,
    type,
    recommendationContext,
    onOpenReader: onRecommendationOpenReader,
    onOpenDetails: onRecommendationOpenDetails,
    onFavorite: onRecommendationFavorite,
  })
  const {
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
    readStatusText,
    setEditOpen,
    setMenuOpen,
    toggleFavorite,
    toggleSelected,
  } = useBaseMediaCardController({
    hasImage,
    id,
    imageSrc,
    isfavorite,
    isnew,
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
  })

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
  const hoverTitleParts = React.useMemo(() => {
    return [
      displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
      displaySummary ? `${t('archive.summary')}: ${displaySummary}` : '',
    ].filter(Boolean)
  }, [displayAllTags, displaySummary, t])

  const shouldEntranceAnimate = index < 24
  const animationDelay = shouldEntranceAnimate ? Math.min(index * 50, 500) : 0
  const detailPath = type === 'archive' ? `/archive?id=${id}` : `/tankoubon?id=${id}`
  const readerTargetId = type === 'archive' ? id : thumbnailId
  const readerPath = readerTargetId
    ? buildReaderPath(readerTargetId, type === 'archive' ? progress : undefined)
    : detailPath
  const progressPercent = pagecount > 0 ? Math.round((progress / pagecount) * 100) : 0

  const navigateToReader = React.useCallback(() => {
    trackOpenReader()
    router.push(readerPath)
  }, [readerPath, router, trackOpenReader])

  const navigateToDetails = React.useCallback(() => {
    trackOpenDetails()
    router.push(detailPath)
  }, [detailPath, router, trackOpenDetails])

  return (
    <>
      <MediaCardActions
        canDelete={canDelete}
        canEdit={canEdit}
        canToggleFavorite={Boolean(onFavoriteToggle)}
        deleting={deleting}
        favoriteLoading={favoriteLoading}
        isFavorite={isFavorite}
        isNew={isNew}
        isNewStatusLoading={isNewStatusLoading}
        menuOpen={menuOpen}
        menuPosition={menuPosition}
        onDelete={handleDelete}
        onDownload={handleDownload}
        onOpenChange={setMenuOpen}
        onOpenEdit={handleOpenEdit}
        onToggleFavorite={toggleFavorite}
        onToggleReadStatus={handleToggleReadStatus}
        onUseMultiSelect={() => toggleSelected(true)}
        onStartReading={navigateToReader}
        readStatusText={readStatusText}
        readerTargetId={readerTargetId}
        selectable={selectable}
        selectionMode={selectionMode}
        t={t}
        type={type}
      />

      <div
        className={[
          'group cursor-pointer motion-reduce:animate-none',
          shouldEntranceAnimate ? 'motion-safe:animate-archive-card-in' : '',
        ].filter(Boolean).join(' ')}
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
        onClick={(event) => {
          if (selectionMode && selectable) {
            event.preventDefault()
            toggleSelected()
            return
          }
          navigateToReader()
        }}
        onContextMenuCapture={(event) => {
          event.preventDefault()
        }}
        onContextMenu={handleContextMenu}
      >
        <Card className={cn('overflow-hidden bg-transparent transition-shadow hover:shadow-lg dark:bg-transparent', surfaceClassName)}>
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
                onContextMenu={(event) => event.preventDefault()}
                onDragStart={(event) => event.preventDefault()}
                onError={handleImageError}
              />
            ) : (
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-muted-foreground">{t('archive.noCover')}</span>
              </div>
            )}

            {selectionMode && !selected && (
              <div className="absolute inset-0 z-1 bg-black/45 pointer-events-none" />
            )}

            {badge && <div className="absolute top-2 left-2 z-30">{badge}</div>}

            {selectable && (
              <div
                className={[
                  'absolute top-2 left-2 z-40 transition-all',
                  selectionMode || selected
                    ? 'opacity-100 translate-y-0 pointer-events-auto'
                    : 'opacity-0 -translate-y-1 pointer-events-none md:group-hover:opacity-100 md:group-hover:translate-y-0 md:group-hover:pointer-events-auto',
                ].join(' ')}
              >
                <button
                  type="button"
                  className={[
                    'inline-flex h-7 w-7 items-center justify-center rounded-full border transition-colors',
                    selected
                      ? 'bg-primary text-primary-foreground border-primary/60 shadow-xs'
                      : 'bg-black/50 text-white border-white/40 hover:bg-black/65',
                  ].join(' ')}
                  onClick={(event) => {
                    event.stopPropagation()
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

            <div
              className={[
                'absolute bottom-3 left-3 z-20 items-center gap-2',
                'flex',
                'opacity-0 translate-y-1 transition-all',
                'group-hover:opacity-100 group-hover:translate-y-0',
              ].join(' ')}
              onClick={(event) => event.stopPropagation()}
            >
              <Button
                size="icon"
                variant="secondary"
                className="h-8 w-8 bg-white/15 text-white hover:bg-white/25"
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
                  'h-8 w-8 bg-white/15 text-white hover:bg-white/25',
                  isFavorite ? 'text-red-400' : '',
                ].filter(Boolean).join(' ')}
                aria-label={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                disabled={favoriteLoading}
                onClick={async (event) => {
                  event.stopPropagation()
                  await toggleFavorite()
                }}
              >
                <Heart className={`h-4 w-4 ${isFavorite ? 'fill-current' : ''}`} />
              </Button>
            </div>

            <div
              className={[
                'pointer-events-none absolute inset-0 z-10 flex items-end bg-linear-to-t from-black/70 via-black/30 to-transparent transition-opacity',
                'opacity-0 group-hover:opacity-100',
              ].join(' ')}
            >
              {(allTags.length > 0 || displaySummary) && (
                <div className="w-full p-3 pb-12 space-y-2">
                  {allTags.length > 0 && (
                    <div
                      className={[
                        'flex flex-wrap gap-1 overflow-hidden',
                        displaySummary ? 'max-h-[48px]' : 'max-h-[72px]',
                      ].join(' ')}
                    >
                      {hoverTags.map((tag) => (
                        <span key={tag} className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white">
                          {stripNamespace(tag)}
                        </span>
                      ))}
                      {allTags.length > hoverTags.length && (
                        <span className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white">
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

        <div className="pt-3">
          <div className="h-5 mb-2">
            <button
              type="button"
              className="block w-full truncate text-left font-semibold text-sm transition-colors hover:underline hover:decoration-current hover:underline-offset-4"
              title={displayTitle}
              aria-label={displayTitle}
              onClick={(event) => {
                event.stopPropagation()
                navigateToDetails()
              }}
            >
              {displayTitle}
            </button>
          </div>
          <div className={['text-xs text-muted-foreground', hideMetaOnMobile ? 'hidden sm:block' : ''].join(' ')}>
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
          onSaved={handleEditSaved}
          thumbnailAssetId={thumbnailAssetId}
          type={type}
        />
      ) : null}
    </>
  )
}
