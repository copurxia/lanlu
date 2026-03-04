'use client';

import { ReactNode } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';

interface SettingsPageWrapperProps {
  title: string;
  description?: string;
  icon?: ReactNode;
  loading?: boolean;
  requireAuth?: boolean;
  requireAdmin?: boolean;
  children: ReactNode;
  actions?: ReactNode;
  empty?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  emptyIcon?: ReactNode;
}

export function SettingsPageWrapper({
  title,
  description,
  icon,
  loading = false,
  requireAuth = true,
  requireAdmin = false,
  children,
  actions,
  empty = false,
  emptyTitle,
  emptyDescription,
  emptyIcon
}: SettingsPageWrapperProps) {
  const { t } = useLanguage();
  const { isAuthenticated, user } = useAuth();

  // 未登录且需要认证
  if (requireAuth && !isAuthenticated) {
    return (
      <div className="space-y-6">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            {icon}
            {title}
          </h2>
          {description && <p className="text-sm text-muted-foreground">{t('auth.loginToManageTokens')}</p>}
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            <div className="text-center text-muted-foreground">
              {t('common.unauthorized')}
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  // 需要管理员权限但用户不是管理员
  if (requireAdmin && !user?.isAdmin) {
    return (
      <div className="space-y-6">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            {icon}
            {title}
          </h2>
          {description && <p className="text-sm text-muted-foreground">{description}</p>}
        </div>
        <Card>
          <CardContent className="pt-6">
            <div className="text-center text-muted-foreground">
              {t('common.accessDenied')}
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  // 加载中
  if (loading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              {icon}
              {title}
            </h2>
            {description && <p className="text-sm text-muted-foreground">{description}</p>}
          </div>
          {actions}
        </div>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-center h-64">
              <RefreshCw className="w-8 h-8 animate-spin text-muted-foreground" />
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  // 空状态
  if (empty) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              {icon}
              {title}
            </h2>
            {description && <p className="text-sm text-muted-foreground">{description}</p>}
          </div>
          {actions}
        </div>
        <Card>
          <CardContent className="pt-6">
            <div className="text-center py-12">
              {emptyIcon}
              {emptyTitle && <p className="mt-4 text-muted-foreground">{emptyTitle}</p>}
              {emptyDescription && <p className="text-sm text-muted-foreground mt-2">{emptyDescription}</p>}
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            {icon}
            {title}
          </h2>
          {description && <p className="text-sm text-muted-foreground">{description}</p>}
        </div>
        {actions}
      </div>
      {children}
    </div>
  );
}
