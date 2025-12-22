'use client';

import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { logger } from '@/lib/logger';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { BookOpen, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { ArchiveService } from '@/lib/archive-service';
import { groupArchivesByTime, TimeGroup } from '@/lib/time-group';
import { Archive } from '@/types/archive';
import { ArchiveCard } from '@/components/archive/ArchiveCard';

export default function ReadingHistoryPage() {
  const { t } = useLanguage();
  const [loading, setLoading] = useState(true);
  const [archives, setArchives] = useState<Archive[]>([]);
  const [groupedArchives, setGroupedArchives] = useState<TimeGroup[]>([]);
  const [error, setError] = useState<string | null>(null);

  // 加载阅读记录
  const loadReadingHistory = useCallback(async (silent = false) => {
    try {
      if (!silent) {
        setLoading(true);
      }
      setError(null);

      // 使用搜索接口获取阅读历史（按最后阅读时间排序会自动过滤出已读档案）
      const response = await ArchiveService.search({
        sortby: 'lastread',
        order: 'desc',
        start: 0,
        count: 1000
      });

      const archiveData = response.data as Archive[];
      setArchives(archiveData);
      // 按时间分组，传入翻译函数
      const grouped = groupArchivesByTime(archiveData, 'lastreadtime', t);
      setGroupedArchives(grouped);
    } catch (err) {
      logger.apiError('readingHistory.loadError', err);
      setError(t('readingHistory.loadError'));
    } finally {
      if (!silent) {
        setLoading(false);
      }
    }
  }, [t]);

  useEffect(() => {
    loadReadingHistory();
  }, [loadReadingHistory]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <BookOpen className="w-5 h-5" />
            {t('settings.readingHistory')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.readingHistoryDescription')}</p>
        </div>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => loadReadingHistory()}
            disabled={loading}
          >
            <RefreshCw className={`w-4 h-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            {t('common.refresh')}
          </Button>
        </div>
      </div>

      <Card>
        <CardContent className="pt-6 space-y-4">
          {error && (
            <div className="text-red-500 mb-4">{error}</div>
          )}

          {loading ? (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
              {Array.from({ length: 10 }).map((_, i) => (
                <div key={i} className="space-y-2">
                  <Skeleton className="aspect-[3/4] w-full" />
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-4 w-2/3" />
                </div>
              ))}
            </div>
          ) : groupedArchives.length === 0 ? (
            <div className="text-center py-12">
              <BookOpen className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
              <p className="text-lg text-muted-foreground">{t('readingHistory.noHistory')}</p>
              <p className="text-sm text-muted-foreground mt-2">{t('readingHistory.noHistoryHint')}</p>
            </div>
          ) : (
            <div className="space-y-8">
              <div className="mb-4 text-sm text-muted-foreground">
                {t('readingHistory.count').replace('{count}', String(archives.length))}
              </div>
              {groupedArchives.map((group) => (
                <div key={group.label} className="space-y-3">
                  <h3 className="text-lg font-semibold">{group.label}</h3>
                  <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                    {group.archives.map((archive, index) => (
                      <ArchiveCard
                        key={archive.arcid}
                        archive={archive}
                        index={index}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
