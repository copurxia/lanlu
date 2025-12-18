'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { LayoutGrid, Package, ListTodo, KeyRound, Users, Tag, Heart, BookOpen, Filter, Server } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';

type SettingsSection = {
  id: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  titleKey: string;
  descriptionKey?: string;
  requiresAdmin?: boolean;
};

const baseSections: SettingsSection[] = [
  { id: 'overview', href: '/settings', icon: LayoutGrid, titleKey: 'settings.overview' },
  { id: 'system', href: '/settings/system', icon: Server, titleKey: 'settings.system.title', requiresAdmin: true },
  { id: 'favorites', href: '/settings/favorites', icon: Heart, titleKey: 'settings.favorites' },
  { id: 'reading-history', href: '/settings/reading-history', icon: BookOpen, titleKey: 'settings.readingHistory' },
  { id: 'auth', href: '/settings/auth', icon: KeyRound, titleKey: 'settings.auth' },
  { id: 'users', href: '/settings/users', icon: Users, titleKey: 'settings.users', requiresAdmin: true },
  { id: 'plugins', href: '/settings/plugins', icon: Package, titleKey: 'settings.plugins', requiresAdmin: true },
  { id: 'tasks', href: '/settings/tasks', icon: ListTodo, titleKey: 'settings.tasks', requiresAdmin: true },
  { id: 'tags', href: '/settings/tags', icon: Tag, titleKey: 'settings.tags', requiresAdmin: true },
  { id: 'smart-filters', href: '/settings/smart-filters', icon: Filter, titleKey: 'settings.smartFilters', requiresAdmin: true },
];

interface SettingsNavProps {
  onNavigate?: () => void;
}

export function SettingsNav({ onNavigate }: SettingsNavProps) {
  const pathname = usePathname() ?? '';
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();

  // Check if current user is admin
  const isAdmin = isAuthenticated && user?.isAdmin === true;

  // Filter sections based on admin status
  const sections = baseSections.filter(section => {
    if (section.requiresAdmin && !isAdmin) {
      return false;
    }
    return true;
  });

  return (
    <nav className="flex flex-col gap-1">
      {sections.map((item) => {
        const Icon = item.icon;
        const isActive =
          item.href === '/settings'
            ? pathname === '/settings'
            : pathname === item.href || pathname.startsWith(`${item.href}/`);

        return (
          <Link
            key={item.id}
            href={item.href}
            onClick={onNavigate}
            className={cn(
              'flex items-center gap-2 px-3 py-2 rounded-md text-sm font-medium transition-colors',
              isActive
                ? 'bg-primary text-primary-foreground'
                : 'text-muted-foreground hover:text-foreground hover:bg-muted'
            )}
          >
            <Icon className="h-4 w-4" />
            <span>{t(item.titleKey)}</span>
          </Link>
        );
      })}
    </nav>
  );
}
