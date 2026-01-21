'use client';

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { Search, Filter, SortAsc, SortDesc, BookOpen, Tag, Calendar, Clock, Star } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { getApiUrl } from '@/lib/api';
import { CategoryService, type Category } from '@/lib/services/category-service';

// 动态加载日期范围选择器以减少初始 JS 体积
const DateRangePicker = dynamic(
  () => import('@/components/ui/date-range-picker').then((m) => m.DateRangePicker),
  {
    ssr: false,
    loading: () => <Skeleton className="h-10 w-full" />,
  }
);

interface SmartFilter {
  id: number;
  name: string;
  translations: Record<string, { text?: string; intro?: string }>;
  icon: string;
  query: string;
  sort_by: string;
  sort_order: string;
  date_from: string;
  date_to: string;
  newonly: boolean;
  untaggedonly: boolean;
}

interface SearchSidebarProps {
  onSearch: (params: {
    query?: string;
    sortBy?: string;
    sortOrder?: string;
    dateFrom?: string;
    dateTo?: string;
    newonly?: boolean;
    untaggedonly?: boolean;
    favoriteonly?: boolean;
    groupby_tanks?: boolean;
    category_id?: string;
  }) => void;
  loading?: boolean;
  filters: {
    sortBy: string;
    sortOrder: string;
    dateFrom: string;
    dateTo: string;
    newonly: boolean;
    untaggedonly: boolean;
    favoriteonly: boolean;
    groupByTanks: boolean;
    categoryId: string;
  };
}

const ICON_MAP: Record<string, React.ComponentType<{ className?: string }>> = {
  BookOpen,
  Tag,
  Calendar,
  Clock,
  Star,
  Filter,
  Search,
};

export function SearchSidebar({ onSearch, loading = false, filters }: SearchSidebarProps) {
  const { t, language } = useLanguage();
  const [sortBy, setSortBy] = useState(filters.sortBy);
  const [sortOrder, setSortOrder] = useState(filters.sortOrder);
  const [dateFrom, setDateFrom] = useState(filters.dateFrom);
  const [dateTo, setDateTo] = useState(filters.dateTo);
  const [newonly, setNewonly] = useState(filters.newonly);
  const [untaggedonly, setUntaggedonly] = useState(filters.untaggedonly);
  const [favoriteonly, setFavoriteonly] = useState(filters.favoriteonly);
  const [groupbyTanks, setGroupbyTanks] = useState(filters.groupByTanks);
  const [selectedCategory, setSelectedCategory] = useState<string>(filters.categoryId || 'all');
  const [categories, setCategories] = useState<Category[]>([]);
  const [smartFilters, setSmartFilters] = useState<SmartFilter[]>([]);
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = useState(false);

  // 设置mounted状态
  useEffect(() => {
    setMounted(true);
  }, []);

  // Keep the form in sync with URL-driven filter state (e.g. on refresh/back/forward).
  useEffect(() => {
    if (!mounted) return;
    setSortBy(filters.sortBy);
    setSortOrder(filters.sortOrder);
    setDateFrom(filters.dateFrom);
    setDateTo(filters.dateTo);
    setNewonly(filters.newonly);
    setUntaggedonly(filters.untaggedonly);
    setFavoriteonly(filters.favoriteonly);
    setGroupbyTanks(filters.groupByTanks);
    setSelectedCategory(filters.categoryId || 'all');
  }, [
    mounted,
    filters.categoryId,
    filters.dateFrom,
    filters.dateTo,
    filters.favoriteonly,
    filters.groupByTanks,
    filters.newonly,
    filters.sortBy,
    filters.sortOrder,
    filters.untaggedonly,
  ]);

  // Load smart filters from API
  useEffect(() => {
    if (!mounted) return;
    const loadSmartFilters = async () => {
      try {
        const response = await fetch(getApiUrl('/api/smart_filters'));
        if (response.ok) {
          const data = await response.json();
          setSmartFilters(data.data?.items || []);
        }
      } catch (error) {
        console.error('Failed to load smart filters:', error);
      }
    };
    loadSmartFilters();
  }, [mounted]);

  // Load categories from API
  useEffect(() => {
    if (!mounted) return;
    const loadCategories = async () => {
      try {
        const cats = await CategoryService.getAllCategories();
        setCategories(cats);
      } catch (error) {
        console.error('Failed to load categories:', error);
      }
    };
    loadCategories();
  }, [mounted]);

  const handleSearch = () => {
    if (!mounted) return;
    onSearch({
      sortBy,
      sortOrder,
      dateFrom,
      dateTo,
      newonly,
      untaggedonly,
      favoriteonly,
      groupby_tanks: groupbyTanks,
      category_id: selectedCategory !== 'all' ? selectedCategory : undefined
    });
  };

  const handleReset = () => {
    if (!mounted) return;
    setSortBy('date_added');
    setSortOrder('desc');
    setDateFrom('');
    setDateTo('');
    setNewonly(false);
    setUntaggedonly(false);
    setFavoriteonly(false);
    setGroupbyTanks(true);
    setSelectedCategory('all');
    onSearch({
      sortBy: 'date_added',
      sortOrder: 'desc',
      dateFrom: '',
      dateTo: '',
      newonly: false,
      untaggedonly: false,
      favoriteonly: false,
      groupby_tanks: true,
      category_id: undefined
    });
  };

  const handleSmartFilterClick = useCallback((filter: SmartFilter) => {
    if (!mounted) return;
    // Calculate date from relative days
    let calculatedDateFrom = '';
    let calculatedDateTo = '';

    if (filter.date_from) {
      const days = parseInt(filter.date_from);
      if (!isNaN(days) && typeof window !== 'undefined') {
        const date = new Date();
        date.setDate(date.getDate() + days);
        calculatedDateFrom = date.toISOString().split('T')[0];
      }
    }

    if (filter.date_to) {
      const days = parseInt(filter.date_to);
      if (!isNaN(days) && typeof window !== 'undefined') {
        const date = new Date();
        date.setDate(date.getDate() + days);
        calculatedDateTo = date.toISOString().split('T')[0];
      }
    }

    // Update local state
    if (filter.sort_by) setSortBy(filter.sort_by);
    if (filter.sort_order) setSortOrder(filter.sort_order);
    setDateFrom(calculatedDateFrom);
    setDateTo(calculatedDateTo);
    setNewonly(filter.newonly);
    setUntaggedonly(filter.untaggedonly);
    setGroupbyTanks(true); // 智能筛选默认启用合集分组

    // Trigger search
    onSearch({
      query: filter.query || undefined,
      sortBy: filter.sort_by || undefined,
      sortOrder: filter.sort_order || undefined,
      dateFrom: calculatedDateFrom || undefined,
      dateTo: calculatedDateTo || undefined,
      newonly: filter.newonly || undefined,
      untaggedonly: filter.untaggedonly || undefined,
      groupby_tanks: true,
    });
  }, [onSearch, mounted]);

  const getFilterIcon = (iconName: string) => {
    const IconComponent = ICON_MAP[iconName] || Filter;
    return <IconComponent className="w-4 h-4 mr-2" />;
  };

  const getFilterName = (filter: SmartFilter) => {
    if (language !== 'zh' && filter.translations?.[language]?.text) {
      return filter.translations[language].text;
    }
    return filter.name;
  };

  return (
    <div className="w-full h-full bg-background p-4 overflow-y-auto">
      <div className="space-y-6">
        {/* 智能分类 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <Filter className="w-5 h-5" />
              {t('search.smartCategory')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {mounted && smartFilters.length > 0 ? (
              smartFilters.map((filter) => (
                <Button
                  key={filter.id}
                  variant="outline"
                  size="sm"
                  className="w-full justify-start"
                  onClick={() => handleSmartFilterClick(filter)}
                >
                  {getFilterIcon(filter.icon)}
                  {getFilterName(filter)}
                </Button>
              ))
            ) : (
              // Fallback to default filters if API returns empty or not mounted
              <>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full justify-start"
                  onClick={() => {
                    if (!mounted) return;
                    setNewonly(true);
                    setUntaggedonly(false);
                    onSearch({ newonly: true });
                  }}
                >
                  <BookOpen className="w-4 h-4 mr-2" />
                  {t('search.unreadArchives')}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full justify-start"
                  onClick={() => {
                    if (!mounted) return;
                    setNewonly(false);
                    setUntaggedonly(true);
                    onSearch({ untaggedonly: true });
                  }}
                >
                  <Tag className="w-4 h-4 mr-2" />
                  {t('search.untaggedArchives')}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full justify-start"
                  onClick={() => {
                    if (!mounted || typeof window === 'undefined') return;
                    const lastWeek = new Date();
                    lastWeek.setDate(lastWeek.getDate() - 7);
                    onSearch({
                      dateFrom: lastWeek.toISOString().split('T')[0],
                      sortBy: 'dateadded',
                      sortOrder: 'desc'
                    });
                  }}
                >
                  <Calendar className="w-4 h-4 mr-2" />
                  {t('search.lastWeek')}
                </Button>
              </>
            )}
          </CardContent>
        </Card>

        {/* 筛选条件（搜索关键词由全局搜索框控制） */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <Filter className="w-5 h-5" />
              {t('search.searchConditions')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {/* 日期范围 */}
            <div className="space-y-2">
              <DateRangePicker
                value={{ from: dateFrom, to: dateTo }}
                onChange={(next) => {
                  setDateFrom(next.from || '');
                  setDateTo(next.to || '');
                }}
                placeholder={t('search.dateRange')}
              />
            </div>

            {/* 分类筛选 */}
            <div className="space-y-2">
              <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                <SelectTrigger aria-label={t('search.categoryFilter')} title={t('search.categoryFilter')}>
                  <SelectValue placeholder={t('search.categoryFilter')} />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t('search.allCategories')}</SelectItem>
                  {categories.filter(cat => cat.enabled).map((category) => (
                    <SelectItem key={category.catid} value={category.catid}>
                      {category.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* 排序 */}
            <div className="space-y-2">
              <Select value={sortBy} onValueChange={setSortBy}>
                <SelectTrigger aria-label={t('search.sortBy')} title={t('search.sortBy')}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="relevance">{t('home.relevance')}</SelectItem>
                  <SelectItem value="lastread">{t('home.lastRead')}</SelectItem>
                  <SelectItem value="date_added">{t('home.dateAdded')}</SelectItem>
                  <SelectItem value="title">{t('home.titleSort')}</SelectItem>
                  <SelectItem value="pagecount">{t('home.pageCount')}</SelectItem>
                  <SelectItem value="_default">{t('settings.smartFilterDefault')}</SelectItem>
                </SelectContent>
              </Select>

              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant={sortOrder === 'asc' ? 'default' : 'outline'}
                  onClick={() => setSortOrder('asc')}
                  className="flex-1"
                >
                  <SortAsc className="w-4 h-4 mr-1" />
                  {t('common.asc')}
                </Button>
                <Button
                  size="sm"
                  variant={sortOrder === 'desc' ? 'default' : 'outline'}
                  onClick={() => setSortOrder('desc')}
                  className="flex-1"
                >
                  <SortDesc className="w-4 h-4 mr-1" />
                  {t('common.desc')}
                </Button>
              </div>
            </div>

            {/* 筛选开关 */}
            <div className="space-y-2 border-t pt-3">
              {/* 仅显示新档案 */}
              <div className="flex items-center justify-between">
                <label htmlFor="newonly" className="text-sm">
                  {t('search.newOnly')}
                </label>
                <Switch
                  id="newonly"
                  checked={newonly}
                  onCheckedChange={setNewonly}
                />
              </div>

              {/* 仅显示无标签档案 */}
              <div className="flex items-center justify-between">
                <label htmlFor="untaggedonly" className="text-sm">
                  {t('search.untaggedOnly')}
                </label>
                <Switch
                  id="untaggedonly"
                  checked={untaggedonly}
                  onCheckedChange={setUntaggedonly}
                />
              </div>

              {/* 仅显示收藏档案 */}
              <div className="flex items-center justify-between">
                <label htmlFor="favoriteonly" className="text-sm">
                  {t('search.favoriteOnly')}
                </label>
                <Switch
                  id="favoriteonly"
                  checked={favoriteonly}
                  onCheckedChange={setFavoriteonly}
                />
              </div>

              {/* 按合集分组 */}
              <div className="flex items-center justify-between">
                <label htmlFor="groupbyTanks" className="text-sm">
                  {t('search.groupByTanks')}
                </label>
                <Switch
                  id="groupbyTanks"
                  checked={groupbyTanks}
                  onCheckedChange={setGroupbyTanks}
                />
              </div>
            </div>

            {/* 操作按钮 */}
            <div className="flex gap-2">
              <Button onClick={handleSearch} disabled={loading} className="flex-1">
                {loading ? t('common.loading') : t('common.filter')}
              </Button>
              <Button variant="outline" onClick={handleReset} disabled={loading}>
                {t('common.reset')}
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
