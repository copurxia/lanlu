'use client';

import { useMemo, useState } from 'react';
import { TaskList } from '@/components/tasks/TaskList';
import { ListTodo, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';

export default function SettingsTasksPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();
  const [refreshKey, setRefreshKey] = useState(0);

  // Check if current user is admin
  const isAdmin = useMemo(() => {
    return isAuthenticated && user?.isAdmin === true;
  }, [isAuthenticated, user?.isAdmin]);

  const handleRefresh = () => {
    setRefreshKey(prev => prev + 1);
  };

  // Redirect to login if not authenticated
  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>{t('settings.tasks')}</CardTitle>
            <CardDescription>{t('auth.loginToManageTokens')}</CardDescription>
          </CardHeader>
        </Card>
      </div>
    );
  }

  // Show access denied if not admin
  if (!isAdmin) {
    return (
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>{t('settings.tasks')}</CardTitle>
            <CardDescription>{t('common.accessDenied')}</CardDescription>
          </CardHeader>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <ListTodo className="w-5 h-5" />
            {t('settings.tasks')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.tasksDescription')}</p>
        </div>

        {/* Mobile: icon button; Desktop: text button */}
        <Button
          variant="outline"
          size="icon"
          onClick={handleRefresh}
          className="sm:hidden shrink-0"
          aria-label={t('common.refresh')}
          title={t('common.refresh')}
        >
          <RefreshCw className="w-4 h-4" />
        </Button>
        <Button
          variant="outline"
          onClick={handleRefresh}
          className="hidden sm:inline-flex items-center space-x-2 shrink-0"
        >
          <RefreshCw className="w-4 h-4" />
          <span>{t('common.refresh')}</span>
        </Button>
      </div>

      <TaskList refreshToken={refreshKey} />
    </div>
  );
}
