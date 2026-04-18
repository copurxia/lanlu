import type { ReactNode } from 'react'
import type { RecommendationItemType, RecommendationScene } from '@/types/recommendation'
import type { MenuItem } from '@/components/ui/unified-menu'

export type BaseMediaCardType = RecommendationItemType

export type MediaCardRecommendationContext = {
  scene: RecommendationScene
  seedEntityType?: RecommendationItemType
  seedEntityId?: string
}

export interface BaseMediaCardProps {
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
  type: BaseMediaCardType
  index?: number
  badge?: ReactNode
  extraBadge?: ReactNode
  detailsLabel?: string
  pagesLabel?: string
  priority?: boolean
  hideMetaOnMobile?: boolean
  disableContentVisibility?: boolean
  coverHeight?: number
  surfaceClassName?: string
  onFavoriteToggle?: (id: string, isFavorite: boolean) => Promise<boolean>
  selectable?: boolean
  selectionMode?: boolean
  selected?: boolean
  onToggleSelect?: (selected: boolean) => void
  onRequestEnterSelection?: () => void
  extraMenuItems?: MenuItem[]
  onCoverAspectRatioChange?: (aspectRatio: number) => void
  recommendationContext?: MediaCardRecommendationContext
  onRecommendationOpenReader?: (itemType: RecommendationItemType, itemId: string) => void
  onRecommendationOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void
  onRecommendationFavorite?: (itemType: RecommendationItemType, itemId: string) => void
}
