"use client"

import * as React from "react"
import { useRouter } from 'next/navigation'
import Image from 'next/image'
import Link from 'next/link'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Eye, Heart } from 'lucide-react'
import { ArchiveService } from '@/lib/services/archive-service'
import { useLanguage } from '@/contexts/LanguageContext'
import { stripNamespace, parseTags } from '@/lib/utils/tag-utils'

export interface BaseMediaCardProps {
  // 基础信息
  id: string
  title: string
  thumbnailId: string
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

  // 收藏回调
  onFavoriteToggle?: (id: string, isFavorite: boolean) => Promise<boolean>
}

export function BaseMediaCard({
  id,
  title,
  thumbnailId,
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
  onFavoriteToggle,
}: BaseMediaCardProps) {
  const router = useRouter()
  const { t } = useLanguage()
  const [isFavorite, setIsFavorite] = React.useState(isfavorite)
  const [favoriteLoading, setFavoriteLoading] = React.useState(false)
  const [imageError, setImageError] = React.useState(false)

  const allTags = React.useMemo(() => parseTags(tags), [tags])
  const displayAllTags = React.useMemo(() => allTags.map(stripNamespace), [allTags])
  const hoverTags = React.useMemo(() => {
    return allTags
      .filter(tag => {
        const stripped = stripNamespace(tag).toLowerCase()
        return !stripped.includes('source') && !tag.toLowerCase().includes('source')
      })
      .slice(0, 8)
  }, [allTags])

  const hoverTitleParts = React.useMemo(() => [
    displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
    summary ? `${t('archive.summary')}: ${summary}` : ''
  ].filter(Boolean), [displayAllTags, summary, t])

  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation()
    if (favoriteLoading || !onFavoriteToggle) return
    setFavoriteLoading(true)
    try {
      const success = await onFavoriteToggle(id, isFavorite)
      if (success) setIsFavorite(!isFavorite)
    } catch (error) {
      console.error('收藏操作失败:', error)
    } finally {
      setFavoriteLoading(false)
    }
  }

  // Avoid promoting hundreds of cards into animation/compositor work during scroll.
  const shouldEntranceAnimate = index < 24
  const animationDelay = shouldEntranceAnimate ? Math.min(index * 50, 500) : 0
  const detailPath = type === 'archive' ? `/archive?id=${id}` : `/tankoubon?id=${id}`
  const readerPath = `/reader?id=${thumbnailId}`
  const imageSrc = thumbnailUrl && thumbnailUrl.trim().length > 0
    ? thumbnailUrl
    : ArchiveService.getThumbnailUrl(thumbnailId)

  return (
    <div
      className={[
        "group cursor-pointer motion-reduce:animate-none",
        shouldEntranceAnimate ? "motion-safe:animate-archive-card-in" : "",
      ].filter(Boolean).join(" ")}
      // `content-visibility` acts like browser-level virtualization for large grids.
      style={{
        animationDelay: shouldEntranceAnimate ? `${animationDelay}ms` : undefined,
        contentVisibility: 'auto',
        containIntrinsicSize: '220px 420px',
      }}
      title={hoverTitleParts.length > 0 ? `${title}\n${hoverTitleParts.join('\n')}` : title}
      onClick={() => router.push(readerPath)}
    >
      <Card className="overflow-hidden transition-shadow hover:shadow-lg">
        <div className="aspect-[3/4] bg-muted relative">
          {!imageError ? (
            <Image
              src={imageSrc}
              alt={title}
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
          {isnew && (
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
            {(allTags.length > 0 || summary) && (
              <div className="w-full p-3 pb-12 space-y-2">
                {/* Reserve space for the floating action buttons on all viewports (mobile has no hover). */}
                {allTags.length > 0 && (
                  <div className="flex flex-wrap gap-1">
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
                {summary && (
                  <div className="text-[11px] leading-snug text-white/90 line-clamp-3">{summary}</div>
                )}
              </div>
            )}
          </div>
        </div>
      </Card>

      {/* Keep the white "card" background scoped to the cover only; meta text renders outside. */}
      <div className="pt-3">
        <div className="h-5 mb-2">
          <h3 className="font-semibold text-sm line-clamp-1" title={title}>
            {title}
          </h3>
        </div>
        <div className={["text-xs text-muted-foreground", hideMetaOnMobile ? "hidden sm:block" : ""].join(" ")}>
          {pagesLabel || t('archive.pages').replace('{count}', String(pagecount))}
          {progress > 0 && ` • ${Math.round((progress / pagecount) * 100)}% ${t('common.read')}`}
        </div>
      </div>
    </div>
  )
}
