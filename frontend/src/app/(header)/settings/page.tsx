'use client';

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { logger } from '@/lib/utils/logger';
import { LayoutGrid, Heart, BookOpen, FileText, Database } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { UserStatsService, UserStats, ReadingTrendItem } from '@/lib/services/user-stats-service';
import { StatsCard } from '@/components/dashboard/StatsCard';
import { RecentActivity } from '@/components/dashboard/RecentActivity';
import { Archive } from '@/types/archive';

const ReadingTrendChart = dynamic(
  () => import('@/components/dashboard/ReadingTrendChart').then((m) => m.ReadingTrendChart),
  {
    ssr: false,
    loading: () => (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Skeleton className="h-5 w-36" />
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-[200px] w-full" />
        </CardContent>
      </Card>
    ),
  }
);

export default function SettingsPage() {
  const { t } = useLanguage();
  const { isAuthenticated } = useAuth();

  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<UserStats | null>(null);
  const [trend, setTrend] = useState<ReadingTrendItem[]>([]);
  const [recentRead, setRecentRead] = useState<Archive[]>([]);
  const [recentFavorites, setRecentFavorites] = useState<Archive[]>([]);

  const loadDashboardData = useCallback(async () => {
    if (!isAuthenticated) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      // 并行加载所有数据
      const [statsData, trendData, activityData] = await Promise.all([
        UserStatsService.getStats(),
        UserStatsService.getReadingTrend(30),
        UserStatsService.getRecentActivity(5)
      ]);

      setStats(statsData);
      setTrend(trendData);
      setRecentRead(activityData.recentRead);
      setRecentFavorites(activityData.recentFavorites);
    } catch (error) {
      logger.apiError('load dashboard data', error);
    } finally {
      setLoading(false);
    }
  }, [isAuthenticated]);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      loadDashboardData();
    }
  }, [loadDashboardData]);

  return (
    <div className="space-y-6">
      {/* 页面标题 */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <LayoutGrid className="w-5 h-5" />
            {t('dashboard.title')}
          </CardTitle>
          <CardDescription>{t('dashboard.description')}</CardDescription>
        </CardHeader>
      </Card>

      {/* 统计卡片区域 */}
      <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
        <StatsCard
          title={t('dashboard.favorites')}
          value={stats?.favoriteCount ?? 0}
          icon={<Heart className="w-5 h-5" />}
          loading={loading}
        />
        <StatsCard
          title={t('dashboard.readArchives')}
          value={stats?.readCount ?? 0}
          icon={<BookOpen className="w-5 h-5" />}
          loading={loading}
        />
        <StatsCard
          title={t('dashboard.totalPagesRead')}
          value={stats?.totalPagesRead ?? 0}
          icon={<FileText className="w-5 h-5" />}
          loading={loading}
        />
        <StatsCard
          title={t('dashboard.totalArchives')}
          value={stats?.totalArchives ?? 0}
          icon={<Database className="w-5 h-5" />}
          loading={loading}
        />
      </div>

      {/* 阅读趋势图表 */}
      <ReadingTrendChart data={trend} loading={loading} />

      {/* 最近活动区域 */}
      <RecentActivity
        recentRead={recentRead}
        recentFavorites={recentFavorites}
        loading={loading}
      />
    </div>
  );
}
