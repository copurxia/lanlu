'use client';

import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { BookOpen, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { ReadingHistoryService } from '@/lib/reading-history-service';
import { Archive } from '@/types/archive';
import { HomeArchiveCard } from '@/components/archive/HomeArchiveCard';

export default function ReadingHistoryPage() {
  const { t } = useLanguage();
  const [loading, setLoading] = useState(true);
  const [archives, setArchives] = useState<Archive[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  // 加载阅读记录
  const loadReadingHistory = async (silent = false) => {
    try {
      if (!silent) {
        setLoading(true);
      }
      setError(null);

      const response = await ReadingHistoryService.getReadArchives(0, 1000);

      if (response.success === 1) {
        setArchives(response.data);
        setTotalCount(response.recordsTotal);
      } else {
        setError(t('readingHistory.loadError'));
      }
    } catch (err) {
      console.error('加载阅读记录失败:', err);
      setError(t('readingHistory.loadError'));
    } finally {
      if (!silent) {
        setLoading(false);
      }
    }
  };

  useEffect(() => {
    loadReadingHistory();
  }, []);

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="flex items-center gap-2">
                <BookOpen className="w-5 h-5" />
                {t('readingHistory.title')}
              </CardTitle>
              <CardDescription>{t('readingHistory.description')}</CardDescription>
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
        </CardHeader>
        <CardContent>
          {error && (
            <div className="text-red-500 mb-4">{error}</div>
          )}

          {loading ? (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
              {Array.from({ length: 10 }).map((_, i) => (
                <div key={i} className="space-y-2">
                  <Skeleton className="aspect-[3/4] w-full" />
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-4 w-2/3" />
                </div>
              ))}
            </div>
          ) : archives.length === 0 ? (
            <div className="text-center py-12">
              <BookOpen className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
              <p className="text-lg text-muted-foreground">{t('readingHistory.noHistory')}</p>
              <p className="text-sm text-muted-foreground mt-2">{t('readingHistory.noHistoryHint')}</p>
            </div>
          ) : (
            <div>
              <div className="mb-4 text-sm text-muted-foreground">
                {t('readingHistory.count').replace('{count}', String(archives.length))}
              </div>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
                {archives.map((archive) => (
                  <HomeArchiveCard
                    key={archive.arcid}
                    archive={archive}
                  />
                ))}
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
