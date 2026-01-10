'use client';

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { SearchInput } from '@/components/ui/search-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { Search, Filter, SortAsc, SortDesc, BookOpen, Tag, Calendar, Clock, Star, FolderOpen } from 'lucide-react';
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

export function SearchSidebar({ onSearch, loading = false }: SearchSidebarProps) {
  const { t, language } = useLanguage();
  const [query, setQuery] = useState('');
  const [sortBy, setSortBy] = useState('date_added');
  const [sortOrder, setSortOrder] = useState('desc');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [newonly, setNewonly] = useState(false);
  const [untaggedonly, setUntaggedonly] = useState(false);
  const [favoriteonly, setFavoriteonly] = useState(false);
  const [groupbyTanks, setGroupbyTanks] = useState(true);
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [categories, setCategories] = useState<Category[]>([]);
  const [smartFilters, setSmartFilters] = useState<SmartFilter[]>([]);
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = useState(false);

  // 设置mounted状态
  useEffect(() => {
    setMounted(true);
  }, []);

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
      query,
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
    setQuery('');
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
      query: '',
      sortBy: 'date_added',
      sortOrder: 'desc',
      newonly: false,
      untaggedonly: false,
      favoriteonly: false,
      groupby_tanks: true
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
    setQuery(filter.query || '');
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

        {/* 搜索框 */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center gap-2">
              <Search className="w-5 h-5" />
              {t('search.title')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <SearchInput
              placeholder={t('search.keywordPlaceholder')}
              value={query}
              onChange={setQuery}
            />

            {/* 日期范围 */}
            <div className="space-y-3">
              <label className="text-sm font-medium flex items-center gap-2">
                <Calendar className="w-4 h-4 text-muted-foreground" />
                {t('search.dateRange')}
              </label>

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
              <label className="text-sm font-medium flex items-center gap-2">
                <FolderOpen className="w-4 h-4 text-muted-foreground" />
                {t('search.categoryFilter')}
              </label>
              <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                <SelectTrigger>
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
              <label className="text-sm font-medium">{t('search.sortBy')}</label>
              <Select value={sortBy} onValueChange={setSortBy}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
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
                {loading ? t('common.loading') : t('common.search')}
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
