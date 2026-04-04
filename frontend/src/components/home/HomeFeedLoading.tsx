'use client';

import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils/utils';

function FeedMediaPlaceholder({
  className,
  label,
}: {
  className?: string;
  label?: string;
}) {
  return (
    <div className={cn('feed-shimmer relative overflow-hidden bg-muted/80', className)}>
      <div className="absolute inset-0 bg-linear-to-br from-background/10 via-transparent to-foreground/5" />
      {label ? (
        <div className="absolute inset-x-4 bottom-4 rounded-full bg-background/75 px-3 py-1 text-xs text-muted-foreground shadow-xs backdrop-blur-sm">
          {label}
        </div>
      ) : null}
    </div>
  );
}

function FeedLoadingLine({
  className,
}: {
  className?: string;
}) {
  return <Skeleton className={cn('feed-shimmer h-4 rounded-full', className)} />;
}

export function TweetFeedSkeleton({
  count = 4,
  append = false,
}: {
  count?: number;
  append?: boolean;
}) {
  return (
    <div className={cn('space-y-4', append && 'pt-2')}>
      {Array.from({ length: count }).map((_, index) => (
        <div
          key={`tweet-skeleton-${index}`}
          className="feed-card-enter rounded-2xl border bg-card px-4 py-4 shadow-xs sm:px-5"
        >
          <div className="flex items-start gap-3">
            <Skeleton className="feed-shimmer h-11 w-11 shrink-0 rounded-full" />
            <div className="min-w-0 flex-1 space-y-3">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1 space-y-2">
                  <FeedLoadingLine className="w-36 max-w-[60%]" />
                  <FeedLoadingLine className="h-3 w-24 max-w-[35%]" />
                </div>
                <div className="flex items-center gap-2">
                  <Skeleton className="feed-shimmer h-8 w-8 rounded-full" />
                  <Skeleton className="feed-shimmer h-8 w-8 rounded-full" />
                  <Skeleton className="feed-shimmer h-8 w-8 rounded-full" />
                </div>
              </div>
              <div className="space-y-2">
                <FeedLoadingLine className="w-full" />
                <FeedLoadingLine className="w-[92%]" />
                <FeedLoadingLine className="w-[68%]" />
              </div>
              <div className="flex flex-wrap gap-2">
                <Skeleton className="feed-shimmer h-6 w-16 rounded-full" />
                <Skeleton className="feed-shimmer h-6 w-20 rounded-full" />
                <Skeleton className="feed-shimmer h-6 w-14 rounded-full" />
              </div>
              <FeedMediaPlaceholder className="aspect-16/10 w-full rounded-2xl" />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

export function ChannelFeedSkeleton({
  count = 3,
  append = false,
}: {
  count?: number;
  append?: boolean;
}) {
  return (
    <div className={cn('space-y-4', append && 'pt-2')}>
      {Array.from({ length: count }).map((_, index) => (
        <div key={`channel-skeleton-${index}`} className="feed-card-enter px-1 py-2">
          <div className="flex items-end gap-3">
            <Skeleton className="feed-shimmer h-10 w-10 shrink-0 rounded-full" />
            <div className="min-w-0 flex-1 overflow-hidden rounded-[1.75rem] rounded-bl-md border border-border/70 bg-card/95 shadow-[0_16px_40px_hsl(var(--foreground)/0.08)] backdrop-blur-sm dark:bg-card/88 dark:shadow-[0_20px_48px_hsl(220_40%_2%/0.35)]">
              <FeedMediaPlaceholder className="aspect-16/10 w-full" />
              <div className="space-y-3 px-4 py-3 sm:px-5">
                <div className="space-y-2">
                  <FeedLoadingLine className="w-full" />
                  <FeedLoadingLine className="w-[88%]" />
                  <FeedLoadingLine className="w-[58%]" />
                </div>
                <div className="flex flex-wrap gap-2">
                  <Skeleton className="feed-shimmer h-6 w-16 rounded-full" />
                  <Skeleton className="feed-shimmer h-6 w-20 rounded-full" />
                  <Skeleton className="feed-shimmer h-6 w-14 rounded-full" />
                </div>
                <div className="flex justify-end">
                  <FeedLoadingLine className="h-3 w-28" />
                </div>
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

export function FeedPreviewPlaceholder({
  className,
  label,
}: {
  className?: string;
  label?: string;
}) {
  return <FeedMediaPlaceholder className={className} label={label} />;
}
