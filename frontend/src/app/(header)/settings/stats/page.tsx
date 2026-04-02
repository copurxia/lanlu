'use client';

import { useEffect, useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import { useRouter } from 'next/navigation';
import { BarChart3 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { useServerInfo } from '@/contexts/ServerInfoContext';
import { TagService } from '@/lib/services/tag-service';
import { logger } from '@/lib/utils/logger';
import { buildExactTagSearchQuery } from '@/lib/utils/tag-utils';
import { SettingsPageWrapper } from '@/components/settings/SettingsPageWrapper';

type CloudItem = { tag: string; display: string; count: number };

const WordCloud = dynamic(
  () => import('@/components/charts/WordCloud').then((m) => m.WordCloud),
  {
    ssr: false,
    loading: () => <Skeleton className="h-[320px] w-full rounded-xl" />,
  }
);

export default function ServerInfoSettingsPage() {
  const { t, language } = useLanguage();
  const router = useRouter();
  const { user, isAuthenticated } = useAuth();
  const { serverInfo, refresh } = useServerInfo();

  const isAdmin = useMemo(() => isAuthenticated && user?.isAdmin === true, [isAuthenticated, user?.isAdmin]);

  const [cloudLoading, setCloudLoading] = useState(false);
  const [cloudItems, setCloudItems] = useState<CloudItem[]>([]);

  useEffect(() => {
    if (!isAuthenticated || !isAdmin) return;
    let cancelled = false;

    (async () => {
      setCloudLoading(true);
      try {
        const res = await TagService.getCloud({ lang: language, limit: 200 });
        if (!cancelled) setCloudItems(res.items || []);
      } catch (e) {
        logger.apiError('fetch tag cloud', e);
        if (!cancelled) setCloudItems([]);
      } finally {
        if (!cancelled) setCloudLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [isAdmin, isAuthenticated, language]);

  const actions = (
    <Button variant="outline" onClick={refresh}>
      {t('common.refresh')}
    </Button>
  );

  return (
    <SettingsPageWrapper
      title={t('settings.stats')}
      description={t('settings.statsDescription')}
      icon={<BarChart3 className="w-5 h-5" />}
      requireAuth
      requireAdmin
      actions={actions}
    >
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">{t('settings.statsSystem')}</CardTitle>
        </CardHeader>
        <CardContent className="pt-0">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
            <div className="flex items-center justify-between gap-3">
              <span className="text-muted-foreground">{t('settings.serverName')}</span>
              <span className="truncate">{serverInfo?.name ?? '-'}</span>
            </div>
            <div className="flex items-center justify-between gap-3">
              <span className="text-muted-foreground">{t('settings.serverVersion')}</span>
              <span className="truncate">{serverInfo?.version_desc ?? serverInfo?.version ?? '-'}</span>
            </div>
            <div className="flex items-center justify-between gap-3">
              <span className="text-muted-foreground">{t('settings.serverArchives')}</span>
              <span>{serverInfo?.total_archives ?? '-'}</span>
            </div>
            <div className="flex items-center justify-between gap-3">
              <span className="text-muted-foreground">{t('settings.serverPagesRead')}</span>
              <span>{serverInfo?.total_pages_read ?? '-'}</span>
            </div>
            <div className="flex items-center justify-between gap-3 sm:col-span-2">
              <span className="text-muted-foreground">{t('settings.dbExtensions')}</span>
              {!serverInfo?.db_extensions || serverInfo.db_extensions.length === 0 ? (
                <span>-</span>
              ) : (
                <span className="flex flex-wrap justify-end gap-1.5">
                  {serverInfo.db_extensions.map((ext) => (
                    <Badge
                      key={ext.name}
                      variant={ext.enabled ? 'default' : 'outline'}
                      title={ext.enabled && ext.version ? `${ext.name} ${ext.version}` : ext.name}
                    >
                      {ext.name}
                    </Badge>
                  ))}
                </span>
              )}
            </div>
          </div>
          {serverInfo?.motd ? (
            <div className="mt-3 text-sm text-muted-foreground whitespace-pre-wrap">{serverInfo.motd}</div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">{t('settings.tagCloud')}</CardTitle>
        </CardHeader>
        <CardContent className="pt-0">
          {cloudLoading ? (
            <div className="py-8 text-center text-muted-foreground">{t('common.loading')}</div>
          ) : cloudItems.length === 0 ? (
            <div className="py-8 text-center text-muted-foreground">{t('settings.tagCloudEmpty')}</div>
          ) : (
            <WordCloud
              items={cloudItems.map((i) => ({ id: i.tag, text: i.display, weight: i.count, meta: i.tag }))}
              onWordClick={(meta) => {
                const exactQuery = buildExactTagSearchQuery(String(meta || ''));
                if (!exactQuery) return;
                router.push(`/?q=${encodeURIComponent(exactQuery)}`);
              }}
              ariaLabel={t('settings.tagCloud')}
            />
          )}
        </CardContent>
      </Card>
    </SettingsPageWrapper>
  );
}
