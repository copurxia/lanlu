'use client';

import { TaskList } from '@/components/tasks/TaskList';
import { ListTodo } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

export default function SettingsTasksPage() {
  const { t } = useLanguage();

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

