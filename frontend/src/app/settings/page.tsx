'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ArrowRight, LayoutGrid, Package, ListTodo, Tag, Heart, BookOpen } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';

export default function SettingsPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();
  const isAdmin = isAuthenticated && user?.isAdmin === true;

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <LayoutGrid className="w-5 h-5" />
            {t('settings.overview')}
          </CardTitle>
          <CardDescription>{t('settings.overviewDescription')}</CardDescription>
        </CardHeader>
      </Card>

      <div className="grid gap-4 md:grid-cols-2">
        <Card className="h-full">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Heart className="w-5 h-5" />
              {t('settings.favorites')}
            </CardTitle>
            <CardDescription>{t('settings.favoritesDescription')}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button asChild className="w-full justify-between">
              <Link href="/settings/favorites">
                <span>{t('common.open')}</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </Button>
          </CardContent>
        </Card>

        <Card className="h-full">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <BookOpen className="w-5 h-5" />
              {t('settings.readingHistory')}
            </CardTitle>
            <CardDescription>{t('settings.readingHistoryDescription')}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button asChild className="w-full justify-between">
              <Link href="/settings/reading-history">
                <span>{t('common.open')}</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </Button>
          </CardContent>
        </Card>

        <Card className="h-full">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Package className="w-5 h-5" />
              {t('settings.plugins')}
            </CardTitle>
            <CardDescription>{t('settings.pluginsDescription')}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button asChild className="w-full justify-between">
              <Link href="/settings/plugins">
                <span>{t('common.open')}</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </Button>
          </CardContent>
        </Card>

        {isAdmin && (
          <Card className="h-full">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Tag className="w-5 h-5" />
                {t('settings.tagI18n')}
              </CardTitle>
              <CardDescription>{t('settings.tagI18nDescription')}</CardDescription>
            </CardHeader>
            <CardContent>
              <Button asChild className="w-full justify-between">
                <Link href="/settings/tag-i18n">
                  <span>{t('common.open')}</span>
                  <ArrowRight className="w-4 h-4" />
                </Link>
              </Button>
            </CardContent>
          </Card>
        )}

        <Card className="h-full">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <ListTodo className="w-5 h-5" />
              {t('settings.tasks')}
            </CardTitle>
            <CardDescription>{t('settings.tasksDescription')}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button asChild className="w-full justify-between">
              <Link href="/settings/tasks">
                <span>{t('common.open')}</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
