import { useEffect } from 'react';
import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';
import { ArchiveCard } from './ArchiveCard';
import { TankoubonCard } from '../tankoubon/TankoubonCard';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { useLanguage } from '@/contexts/LanguageContext';

// Type guard to check if an item is a Tankoubon
function isTankoubon(item: any): item is Tankoubon {
  return item && 'tankoubon_id' in item;
}

interface ArchiveGridProps {
  archives: (Archive | Tankoubon)[];
  variant?: 'default' | 'home' | 'random';
  preloadTankoubonDetails?: boolean; // 新增选项
  priorityCount?: number; // 首屏优先加载的图片数量（用于 LCP 优化）
}

export function ArchiveGrid({
  archives,
  variant = 'default',
  preloadTankoubonDetails = true,  // 默认启用预加载
  priorityCount = 0  // 默认不优先加载，首页可传入首屏可见卡片数
}: ArchiveGridProps) {
  const { t } = useLanguage();

  // 预加载 tankoubon 详细信息
  useEffect(() => {
    if (!preloadTankoubonDetails) return;

    const tankoubonIds = archives
      .filter(isTankoubon)
      .map(t => t.tankoubon_id)
      // Prevent overfetching when a page contains many collections.
      .slice(0, 50);

    if (tankoubonIds.length > 0) {
      let cancelled = false;
      const run = () => {
        if (cancelled) return;
        // 在后台预加载数据，但不影响首屏交互
        TankoubonService.getTankoubonsWithArchives(tankoubonIds).catch((err) =>
          console.warn('预加载 tankoubon 详情失败:', err)
        );
      };

      // Prefer idle time so this doesn't compete with first paint / input.
      if (typeof window !== 'undefined' && 'requestIdleCallback' in window) {
        const handle = (window as any).requestIdleCallback(run, { timeout: 2000 });
        return () => {
          cancelled = true;
          (window as any).cancelIdleCallback?.(handle);
        };
      }

      const t = setTimeout(run, 0);
      return () => {
        cancelled = true;
        clearTimeout(t);
      };
    }
  }, [archives, preloadTankoubonDetails]);

  if (archives.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-muted-foreground">{t('archive.noArchives')}</p>
      </div>
    );
  }

  // 根据不同变体使用不同的网格布局
  const gridClasses = variant === 'random'
    ? 'grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4'
    : 'grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4';

  return (
    <div className={gridClasses}>
      {archives.map((item, index) => {
        if (isTankoubon(item)) {
          return (
            <TankoubonCard
              key={item.tankoubon_id}
              tankoubon={item}
              priority={index < priorityCount}
            />
          );
        } else {
          const compactMobile = variant === 'home' || variant === 'random';
          return (
            <ArchiveCard
              key={item.arcid}
              archive={item}
              index={index}
              priority={index < priorityCount}
              compactMobile={compactMobile}
            />
          );
        }
      })}
    </div>
  );
}
