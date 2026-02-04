"use client"

import * as React from "react"
import { useRouter } from 'next/navigation'
import Image from 'next/image'
import Link from 'next/link'
import { Card, CardContent, CardFooter } from '@/components/ui/card'
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
  hideActionsOnMobile?: boolean

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
  hideActionsOnMobile = false,
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
    <Card
      className={[
        "group overflow-hidden cursor-pointer transition-shadow hover:shadow-lg motion-reduce:animate-none",
        shouldEntranceAnimate ? "motion-safe:animate-archive-card-in" : "",
      ].filter(Boolean).join(" ")}
      // `content-visibility` acts like browser-level virtualization for large grids.
      style={{
        animationDelay: shouldEntranceAnimate ? `${animationDelay}ms` : undefined,
        contentVisibility: 'auto',
        containIntrinsicSize: '220px 360px',
      }}
      title={hoverTitleParts.length > 0 ? `${title}\n${hoverTitleParts.join('\n')}` : title}
      onClick={() => router.push(readerPath)}
    >
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
        {badge && <div className="absolute top-2 left-2">{badge}</div>}
        {isnew && (
          <Badge className="absolute top-2 right-2 bg-red-500">
            {t('archive.new')}
          </Badge>
        )}
        {extraBadge && <div className="absolute bottom-2 right-2">{extraBadge}</div>}

        {/* Hover overlay */}
        {(allTags.length > 0 || summary) && (
          <div className="pointer-events-none absolute inset-0 flex items-end bg-gradient-to-t from-black/70 via-black/30 to-transparent opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">
            <div className="w-full p-3 space-y-2">
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
          </div>
        )}
      </div>

      <CardContent className="p-4">
        <div className="h-10 mb-2">
          <h3 className="font-semibold text-sm line-clamp-2" title={title}>
            {title}
          </h3>
        </div>
        <div className={["text-xs text-muted-foreground", hideMetaOnMobile ? "hidden sm:block" : ""].join(" ")}>
          {pagesLabel || t('archive.pages').replace('{count}', String(pagecount))}
          {progress > 0 && ` • ${Math.round((progress / pagecount) * 100)}% ${t('common.read')}`}
        </div>
      </CardContent>

      <CardFooter className={["p-4 pt-0 flex gap-2", hideActionsOnMobile ? "hidden sm:flex" : ""].join(" ")}>
        <Button
          asChild
          size="sm"
          className="flex-1"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Avoid prefetching N distinct URLs like `/archive?id=...` for large grids. */}
          <Link href={detailPath} prefetch={false}>
            <Eye className="w-4 h-4 mr-2" />
            {detailsLabel || t('archive.details')}
          </Link>
        </Button>
        <Button
          size="sm"
          variant="outline"
          className={`px-3 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
          title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
          disabled={favoriteLoading}
          onClick={handleFavoriteClick}
        >
          <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
        </Button>
      </CardFooter>
    </Card>
  )
}
