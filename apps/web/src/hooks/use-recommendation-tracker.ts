import * as React from 'react'
import type { MediaCardRecommendationContext } from '@/components/ui/base-media-card.types'
import type { RecommendationItemType } from '@/types/recommendation'

type RecommendationHandler = (itemType: RecommendationItemType, itemId: string) => void

type UseRecommendationTrackerOptions = {
  id: string
  type: RecommendationItemType
  recommendationContext?: MediaCardRecommendationContext
  onOpenReader?: RecommendationHandler
  onOpenDetails?: RecommendationHandler
  onFavorite?: RecommendationHandler
}

export function useRecommendationTracker({
  id,
  type,
  recommendationContext,
  onOpenReader,
  onOpenDetails,
  onFavorite,
}: UseRecommendationTrackerOptions) {
  const trackingEnabled = Boolean(recommendationContext)

  const trackOpenReader = React.useCallback(() => {
    if (!trackingEnabled) return
    onOpenReader?.(type, id)
  }, [id, onOpenReader, trackingEnabled, type])

  const trackOpenDetails = React.useCallback(() => {
    if (!trackingEnabled) return
    onOpenDetails?.(type, id)
  }, [id, onOpenDetails, trackingEnabled, type])

  const trackFavorite = React.useCallback(() => {
    if (!trackingEnabled) return
    onFavorite?.(type, id)
  }, [id, onFavorite, trackingEnabled, type])

  return {
    trackingEnabled,
    trackOpenReader,
    trackOpenDetails,
    trackFavorite,
  }
}
