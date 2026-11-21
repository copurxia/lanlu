'use client';

import { ReactNode } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { LucideIcon } from 'lucide-react';

interface AuthGuardProps {
  isAuthenticated: boolean;
  isAdmin?: boolean;
  requireAdmin?: boolean; // 是否需要管理员权限
  title: string;
  description?: string;
  icon: LucideIcon;
  t: (key: string) => string;
  children: ReactNode;
}

/**
 * 认证保护组件
 * 用于保护需要登录或管理员权限的页面
 */
export function AuthGuard({
  isAuthenticated,
  isAdmin = false,
  requireAdmin = false,
  title,
  icon: Icon,
  t,
  children
}: AuthGuardProps) {
  // 未认证状态
  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Icon className="w-5 h-5" />
              {title}
            </h2>
            <p className="text-sm text-muted-foreground">{t('auth.loginToManageTokens')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            {/* Empty content */}
          </CardContent>
        </Card>
      </div>
    );
  }

  // 需要管理员权限但用户不是管理员
  if (requireAdmin && !isAdmin) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Icon className="w-5 h-5" />
              {title}
            </h2>
            <p className="text-sm text-muted-foreground">{t('common.accessDenied')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            {/* Empty content */}
          </CardContent>
        </Card>
      </div>
    );
  }

  return <>{children}</>;
}
