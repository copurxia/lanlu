'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { BookOpen, Heart } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { Archive } from '@/types/archive';
import Link from 'next/link';
import Image from 'next/image';

interface RecentActivitySectionProps {
  title: string;
  icon: React.ReactNode;
  archives: Archive[];
  loading?: boolean;
  emptyMessage: string;
}

function RecentActivitySection({ title, icon, archives, loading = false, emptyMessage }: RecentActivitySectionProps) {
  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            {icon}
            <Skeleton className="h-5 w-20" />
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {[1, 2, 3].map((i) => (
              <div key={i} className="flex items-center gap-3">
                <Skeleton className="w-12 h-16 rounded" />
                <Skeleton className="h-4 flex-1" />
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base">
          {icon}
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {archives.length > 0 ? (
          <div className="space-y-3">
            {archives.map((archive) => (
              <Link
                key={archive.arcid}
                href={`/archive?id=${archive.arcid}`}
                className="flex items-center gap-3 p-2 rounded-lg hover:bg-accent transition-colors"
              >
                <div className="relative w-12 h-16 flex-shrink-0 rounded overflow-hidden bg-muted">
                  <Image
                    src={`/api/archives/${archive.arcid}/thumbnail`}
                    alt={archive.title}
                    fill
                    className="object-cover"
                    sizes="48px"
                  />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{archive.title}</p>
                  <p className="text-xs text-muted-foreground">
                    {archive.pagecount} 页
                    {archive.progress > 0 && ` · 已读 ${archive.progress} 页`}
                  </p>
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <div className="py-8 text-center text-muted-foreground text-sm">
            {emptyMessage}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

interface RecentActivityProps {
  recentRead: Archive[];
  recentFavorites: Archive[];
  loading?: boolean;
}

export function RecentActivity({ recentRead, recentFavorites, loading = false }: RecentActivityProps) {
  const { t } = useLanguage();

  return (
    <div className="grid gap-4 md:grid-cols-2">
      <RecentActivitySection
        title={t('dashboard.recentRead')}
        icon={<BookOpen className="w-5 h-5" />}
        archives={recentRead}
        loading={loading}
        emptyMessage={t('dashboard.noRecentRead')}
      />
      <RecentActivitySection
        title={t('dashboard.recentFavorites')}
        icon={<Heart className="w-5 h-5" />}
        archives={recentFavorites}
        loading={loading}
        emptyMessage={t('dashboard.noRecentFavorites')}
      />
    </div>
  );
}
