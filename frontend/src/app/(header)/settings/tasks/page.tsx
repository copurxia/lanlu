'use client';

import { useMemo, useState } from 'react';
import { TaskList } from '@/components/tasks/TaskList';
import { ListTodo, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { SettingsPageWrapper } from '@/components/settings/SettingsPageWrapper';

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

  const actions = (
    <>
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
    </>
  );

  return (
    <SettingsPageWrapper
      title={t('settings.tasks')}
      description={t('settings.tasksDescription')}
      icon={<ListTodo className="w-5 h-5" />}
      requireAuth
      requireAdmin
      actions={actions}
    >
      <TaskList refreshToken={refreshKey} />
    </SettingsPageWrapper>
  );
}
