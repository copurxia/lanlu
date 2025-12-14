'use client';

import { useMemo } from 'react';
import { TaskList } from '@/components/tasks/TaskList';
import { ListTodo } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';

export default function SettingsTasksPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();

  // Check if current user is admin
  const isAdmin = useMemo(() => {
    return isAuthenticated && user?.isAdmin === true;
  }, [isAuthenticated, user?.isAdmin]);

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
      <div className="space-y-1">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          <ListTodo className="w-5 h-5" />
          {t('settings.tasks')}
        </h2>
        <p className="text-sm text-muted-foreground">{t('settings.tasksDescription')}</p>
      </div>

      <TaskList />
    </div>
  );
}

