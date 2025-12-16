'use client';

import { useState, useEffect } from 'react';
import { ArchiveService } from '@/lib/archive-service';
import { ServerInfo } from '@/types/server';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Server, Database, BookOpen, HardDrive, Clock, Heart, Settings } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import Link from 'next/link';

export function Sidebar() {
  const { t } = useLanguage();
  const [serverInfo, setServerInfo] = useState<ServerInfo | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchServerInfo = async () => {
      try {
        const info = await ArchiveService.getServerInfo();
        setServerInfo(info);
      } catch (error) {
        console.error('Failed to fetch server info:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchServerInfo();
  }, []);

  if (loading) {
    return (
      <div className="w-80 bg-background p-4">
        <div className="animate-pulse space-y-4">
          <div className="h-4 bg-muted rounded w-3/4"></div>
          <div className="h-4 bg-muted rounded w-1/2"></div>
          <div className="h-4 bg-muted rounded w-2/3"></div>
        </div>
      </div>
    );
  }

  if (!serverInfo) {
    return (
      <div className="w-80 bg-background p-4">
        <p className="text-muted-foreground">{t('sidebar.loadError')}</p>
      </div>
    );
  }

  return (
    <div className="w-80 bg-background p-4">
      <div className="space-y-6">
        {/* 快捷入口 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg">{t('common.actions')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <Button asChild variant="outline" className="w-full justify-start">
              <Link href="/settings/favorites">
                <Heart className="w-4 h-4 mr-2" />
                {t('settings.favorites')}
              </Link>
            </Button>
            <Button asChild variant="outline" className="w-full justify-start">
              <Link href="/settings">
                <Settings className="w-4 h-4 mr-2" />
                {t('navigation.settings')}
              </Link>
            </Button>
          </CardContent>
        </Card>

        {/* 服务器基本信息 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <Server className="w-5 h-5" />
              {t('sidebar.serverInfo')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div>
              <p className="font-medium">{serverInfo.name}</p>
              <p className="text-sm text-muted-foreground">{serverInfo.version_desc}</p>
              <Badge variant="secondary" className="mt-1">
                v{serverInfo.version}
              </Badge>
            </div>
            
            <div className="text-sm">
              <p className="font-medium mb-1">{t('sidebar.systemMessage')}</p>
              <p className="text-muted-foreground">{serverInfo.motd}</p>
            </div>
          </CardContent>
        </Card>

        {/* 档案统计 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <Database className="w-5 h-5" />
              {t('sidebar.archiveStats')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.totalArchives')}</span>
              <Badge variant="outline">{serverInfo.total_archives}</Badge>
            </div>
            
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.pagesRead')}</span>
              <Badge variant="outline">{serverInfo.total_pages_read}</Badge>
            </div>
            
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.perPage')}</span>
              <Badge variant="outline">{serverInfo.archives_per_page}</Badge>
            </div>
          </CardContent>
        </Card>

        {/* 服务器配置 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <HardDrive className="w-5 h-5" />
              {t('sidebar.serverConfig')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.debugMode')}</span>
              <Badge variant={serverInfo.debug_mode ? "default" : "secondary"}>
                {serverInfo.debug_mode ? t('sidebar.enabled') : t('sidebar.disabled')}
              </Badge>
            </div>
            
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.passwordProtection')}</span>
              <Badge variant={serverInfo.has_password ? "default" : "secondary"}>
                {serverInfo.has_password ? t('sidebar.enabled') : t('sidebar.disabled')}
              </Badge>
            </div>
            
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.imageResize')}</span>
              <Badge variant={serverInfo.server_resizes_images ? "default" : "secondary"}>
                {serverInfo.server_resizes_images ? t('sidebar.enabled') : t('sidebar.disabled')}
              </Badge>
            </div>
            
            <div className="flex items-center justify-between">
              <span className="text-sm">{t('sidebar.progressTracking')}</span>
              <Badge variant={serverInfo.server_tracks_progress ? "default" : "secondary"}>
                {serverInfo.server_tracks_progress ? t('sidebar.enabled') : t('sidebar.disabled')}
              </Badge>
            </div>
          </CardContent>
        </Card>

        {/* 缓存信息 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <Clock className="w-5 h-5" />
              {t('sidebar.cacheInfo')}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-sm">
              <p className="font-medium mb-1">{t('sidebar.lastCleared')}</p>
              <p className="text-muted-foreground">
                {serverInfo.cache_last_cleared
                  ? new Date(serverInfo.cache_last_cleared * 1000).toLocaleString()
                  : t('common.unknown')
                }
              </p>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}