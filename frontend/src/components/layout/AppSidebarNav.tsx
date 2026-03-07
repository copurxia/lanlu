'use client';

import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import {
  Suspense,
  useEffect,
  useMemo,
  useState,
  type ComponentType,
  type ReactNode,
} from 'react';
import {
  BookOpen,
  Calendar,
  Clock,
  Filter,
  Folder,
  FolderOpen,
  Search,
  Star,
  Tag,
} from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { SettingsNav } from '@/components/settings/SettingsNav';
import { useLanguage } from '@/contexts/LanguageContext';
import { CategoryService, type Category } from '@/lib/services/category-service';
import {
  buildSmartFilterHref,
  getSmartFilterName,
  type SmartFilter,
  SmartFilterService,
} from '@/lib/services/smart-filter-service';
import { cn } from '@/lib/utils/utils';
import { logger } from '@/lib/utils/logger';

const ICON_MAP: Record<string, ComponentType<{ className?: string }>> = {
  BookOpen,
  Tag,
  Calendar,
  Clock,
  Star,
  Filter,
  Search,
};

const itemClassName =
  'flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors';

function normalizeParams(params: URLSearchParams): string {
  const normalized = new URLSearchParams(params.toString());
  normalized.delete('page');
  const entries = Array.from(normalized.entries()).sort(([left], [right]) =>
    left.localeCompare(right)
  );
  return new URLSearchParams(entries).toString();
}

function buildCategoryHref(categoryId: string, searchParams: { toString(): string } | null): string {
  const params = new URLSearchParams(searchParams?.toString() || '');
  params.delete('q');
  params.delete('page');
  if (params.get('sortby') === 'relevance') params.delete('sortby');

  if (categoryId === 'all') {
    params.delete('category_id');
  } else {
    params.set('category_id', categoryId);
  }

  const queryString = params.toString();
  return queryString ? `/?${queryString}` : '/';
}

function getSmartFilterIcon(iconName: string) {
  const Icon = ICON_MAP[iconName] || Filter;
  return <Icon className="h-4 w-4" />;
}

function SidebarSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="space-y-2">
      <h2 className="px-3 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {title}
      </h2>
      <div className="space-y-1">{children}</div>
    </section>
  );
}

interface AppSidebarNavProps {
  mode: 'home' | 'settings';
  categories?: Category[];
  categoriesLoading?: boolean;
  activeCategoryId?: string;
  onNavigate?: () => void;
  className?: string;
  /** 当为 true 时，组件内部会获取分类数据 */
  fetchCategories?: boolean;
}

function SidebarSkeleton({ lines = 4 }: { lines?: number }) {
  return (
    <div className="space-y-1">
      {Array.from({ length: lines }).map((_, index) => (
        <div key={index} className="flex items-center gap-3 rounded-lg px-3 py-2">
          <Skeleton className="h-4 w-4 rounded-sm" />
          <Skeleton className="h-4 flex-1" />
          <Skeleton className="h-4 w-8" />
        </div>
      ))}
    </div>
  );
}

function AppSidebarNavFallback({ mode, className }: Pick<AppSidebarNavProps, 'mode' | 'className'>) {
  return (
    <div className={cn('h-full overflow-y-auto bg-background', className)}>
      <div className="space-y-6 px-4 pb-4">
        {mode === 'home' && (
          <>
            <SidebarSection title="...">
              <SidebarSkeleton lines={5} />
            </SidebarSection>
            <SidebarSection title="...">
              <SidebarSkeleton lines={3} />
            </SidebarSection>
          </>
        )}
        {mode === 'settings' && (
          <SidebarSection title="...">
            <SidebarSkeleton lines={5} />
          </SidebarSection>
        )}
      </div>
    </div>
  );
}

function AppSidebarNavContent({
  mode,
  categories: externalCategories = [],
  categoriesLoading: externalCategoriesLoading = false,
  activeCategoryId = 'all',
  onNavigate,
  className,
  fetchCategories = false,
}: AppSidebarNavProps) {
  const pathname = usePathname() ?? '';
  const searchParams = useSearchParams();
  const { t, language } = useLanguage();
  const [smartFilters, setSmartFilters] = useState<SmartFilter[]>([]);
  const [smartFiltersLoading, setSmartFiltersLoading] = useState(true);
  const [internalCategories, setInternalCategories] = useState<Category[]>([]);
  const [internalCategoriesLoading, setInternalCategoriesLoading] = useState(false);

  // 使用外部传入的分类数据或内部获取的数据
  const categories = fetchCategories ? internalCategories : externalCategories;
  const categoriesLoading = fetchCategories ? internalCategoriesLoading : externalCategoriesLoading;

  useEffect(() => {
    let cancelled = false;

    const loadSmartFilters = async () => {
      try {
        setSmartFiltersLoading(true);
        const filters = await SmartFilterService.getPublicFilters();
        if (cancelled) return;
        setSmartFilters(
          filters
            .filter((filter) => filter.enabled !== false)
            .sort((left, right) => (left.sort_order_num ?? 0) - (right.sort_order_num ?? 0))
        );
      } catch (error) {
        if (!cancelled) logger.apiError('load public smart filters', error);
      } finally {
        if (!cancelled) setSmartFiltersLoading(false);
      }
    };

    void loadSmartFilters();

    return () => {
      cancelled = true;
    };
  }, []);

  // 如果需要内部获取分类数据
  useEffect(() => {
    if (!fetchCategories) return;

    let cancelled = false;

    const loadCategories = async () => {
      try {
        setInternalCategoriesLoading(true);
        const cats = await CategoryService.getAllCategories();
        if (cancelled) return;
        setInternalCategories(cats);
      } catch (error) {
        if (!cancelled) logger.apiError('load categories', error);
      } finally {
        if (!cancelled) setInternalCategoriesLoading(false);
      }
    };

    void loadCategories();

    return () => {
      cancelled = true;
    };
  }, [fetchCategories]);

  const enabledCategories = useMemo(
    () =>
      categories
        .filter((category) => category.enabled)
        .sort((left, right) => {
          if (left.sort_order !== right.sort_order) return left.sort_order - right.sort_order;
          return left.name.localeCompare(right.name);
        }),
    [categories]
  );

  const totalCategoryCount = useMemo(
    () => enabledCategories.reduce((total, category) => total + (category.archive_count || 0), 0),
    [enabledCategories]
  );

  const currentHomeKey = useMemo(() => {
    if (pathname !== '/') return '';
    return normalizeParams(new URLSearchParams(searchParams?.toString() || ''));
  }, [pathname, searchParams]);

  const hasSearchQuery = Boolean(searchParams?.get('q'));

  return (
    <div className={cn('h-full overflow-y-auto bg-background', className)}>
      <div className="space-y-6 px-4 pb-4">
        {mode === 'home' && (
          <>
            <SidebarSection title={t('home.categories')}>
              <Link
                href={buildCategoryHref('all', searchParams)}
                onClick={onNavigate}
                className={cn(
                  itemClassName,
                  pathname === '/' && !hasSearchQuery && activeCategoryId === 'all'
                    ? 'bg-primary text-primary-foreground'
                    : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                )}
              >
                <FolderOpen className="h-4 w-4" />
                <span className="min-w-0 flex-1 truncate">{t('settings.all')}</span>
                <span className="text-xs opacity-80">{totalCategoryCount}</span>
              </Link>

              {categoriesLoading ? (
                <SidebarSkeleton lines={4} />
              ) : enabledCategories.length > 0 ? (
                enabledCategories.map((category) => (
                  <Link
                    key={category.catid}
                    href={buildCategoryHref(category.catid, searchParams)}
                    onClick={onNavigate}
                    className={cn(
                      itemClassName,
                      pathname === '/' && !hasSearchQuery && activeCategoryId === category.catid
                        ? 'bg-primary text-primary-foreground'
                        : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                    )}
                  >
                    <Folder className="h-4 w-4" />
                    <span className="min-w-0 flex-1 truncate">{category.name}</span>
                    <span className="text-xs opacity-80">{category.archive_count || 0}</span>
                  </Link>
                ))
              ) : (
                <div className="px-3 py-2 text-sm text-muted-foreground">{t('home.noCategories')}</div>
              )}
            </SidebarSection>

            <SidebarSection
              title={
                smartFilters.length > 0
                  ? `${t('search.smartCategory')} (${smartFilters.length})`
                  : t('search.smartCategory')
              }
            >
              {smartFiltersLoading ? (
                <SidebarSkeleton lines={3} />
              ) : smartFilters.length > 0 ? (
                smartFilters.map((filter) => {
                  const href = buildSmartFilterHref(filter);
                  const isActive =
                    pathname === '/' &&
                    normalizeParams(new URLSearchParams(href.split('?')[1] || '')) === currentHomeKey;

                  return (
                    <Link
                      key={filter.id}
                      href={href}
                      onClick={onNavigate}
                      className={cn(
                        itemClassName,
                        isActive
                          ? 'bg-primary text-primary-foreground'
                          : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                      )}
                    >
                      {getSmartFilterIcon(filter.icon)}
                      <span className="min-w-0 flex-1 truncate">
                        {getSmartFilterName(filter, language)}
                      </span>
                    </Link>
                  );
                })
              ) : (
                <div className="px-3 py-2 text-sm text-muted-foreground">{t('common.noData')}</div>
              )}
            </SidebarSection>
          </>
        )}

        {mode === 'settings' && (
          <SidebarSection title={t('navigation.settings')}>
            <SettingsNav onNavigate={onNavigate} />
          </SidebarSection>
        )}
      </div>
    </div>
  );
}

export function AppSidebarNav(props: AppSidebarNavProps) {
  return (
    <Suspense fallback={<AppSidebarNavFallback mode={props.mode} className={props.className} />}>
      <AppSidebarNavContent {...props} />
    </Suspense>
  );
}
