import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';
import { ArchiveCard } from './ArchiveCard';
import { TankoubonCard } from '../tankoubon/TankoubonCard';
import { useLanguage } from '@/contexts/LanguageContext';

// Type guard to check if an item is a Tankoubon
function isTankoubon(item: any): item is Tankoubon {
  return 'tankoubon_id' in item && 'archive_count' in item;
}

interface ArchiveGridProps {
  archives: (Archive | Tankoubon)[];
  variant?: 'default' | 'home' | 'random';
}

export function ArchiveGrid({ archives, variant = 'default' }: ArchiveGridProps) {
  const { t } = useLanguage();

  if (archives.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-muted-foreground">{t('archive.noArchives')}</p>
      </div>
    );
  }

  // 根据不同变体使用不同的网格布局
  const gridClasses = variant === 'random'
    ? 'grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4'
    : 'grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4';

  const tagsDisplay = variant === 'home' ? 'hover' : 'inline';

  return (
    <div className={gridClasses}>
      {archives.map((item) => {
        if (isTankoubon(item)) {
          return (
            <TankoubonCard
              key={item.tankoubon_id}
              tankoubon={item}
              tagsDisplay={tagsDisplay}
            />
          );
        } else {
          return (
            <ArchiveCard
              key={item.arcid}
              archive={item}
              tagsDisplay={tagsDisplay}
            />
          );
        }
      })}
    </div>
  );
}
