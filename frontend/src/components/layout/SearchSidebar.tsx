'use client';

import { useEffect, useState } from 'react';
import dynamic from 'next/dynamic';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { SortAsc, SortDesc } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { cn } from '@/lib/utils/utils';

const DateRangePicker = dynamic(
  () => import('@/components/ui/date-range-picker').then((m) => m.DateRangePicker),
  {
    ssr: false,
    loading: () => <Skeleton className="h-10 w-full" />,
  }
);

interface SearchSidebarProps {
  noPadding?: boolean;
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

export function SearchSidebar({ onSearch, loading = false, filters, noPadding = false }: SearchSidebarProps) {
  const { t } = useLanguage();
  const [sortBy, setSortBy] = useState(filters.sortBy);
  const [sortOrder, setSortOrder] = useState(filters.sortOrder);
  const [dateFrom, setDateFrom] = useState(filters.dateFrom);
  const [dateTo, setDateTo] = useState(filters.dateTo);
  const [newonly, setNewonly] = useState(filters.newonly);
  const [untaggedonly, setUntaggedonly] = useState(filters.untaggedonly);
  const [favoriteonly, setFavoriteonly] = useState(filters.favoriteonly);
  const [groupbyTanks, setGroupbyTanks] = useState(filters.groupByTanks);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

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
  }, [
    mounted,
    filters.dateFrom,
    filters.dateTo,
    filters.favoriteonly,
    filters.groupByTanks,
    filters.newonly,
    filters.sortBy,
    filters.sortOrder,
    filters.untaggedonly,
  ]);

  const handleSearch = () => {
    if (!mounted) return;

    const categoryParam = filters.categoryId !== 'all' ? filters.categoryId : undefined;
    onSearch({
      sortBy,
      sortOrder,
      dateFrom,
      dateTo,
      newonly,
      untaggedonly,
      favoriteonly,
      groupby_tanks: groupbyTanks,
      category_id: categoryParam,
    });
  };

  const handleReset = () => {
    if (!mounted) return;

    const categoryParam = filters.categoryId !== 'all' ? filters.categoryId : undefined;
    setSortBy('date_added');
    setSortOrder('desc');
    setDateFrom('');
    setDateTo('');
    setNewonly(false);
    setUntaggedonly(false);
    setFavoriteonly(false);
    setGroupbyTanks(true);
    onSearch({
      sortBy: 'date_added',
      sortOrder: 'desc',
      dateFrom: '',
      dateTo: '',
      newonly: false,
      untaggedonly: false,
      favoriteonly: false,
      groupby_tanks: true,
      category_id: categoryParam,
    });
  };

  return (
    <div className={cn("space-y-4 pt-4", noPadding ? "" : "px-4 pb-4 sm:p-4")}>
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

      <div className="space-y-2">
        <Select value={sortBy} onValueChange={setSortBy}>
          <SelectTrigger aria-label={t('search.sortBy')} title={t('search.sortBy')}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="relevance">{t('home.relevance')}</SelectItem>
            <SelectItem value="lastread">{t('home.lastRead')}</SelectItem>
            <SelectItem value="date_added">{t('home.dateAdded')}</SelectItem>
            <SelectItem value="updated_at">{t('home.updatedAt')}</SelectItem>
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

      <div className="space-y-2 border-y py-3">
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

      <div className="flex gap-2">
        <Button onClick={handleSearch} disabled={loading} className="flex-1">
          {loading ? t('common.loading') : t('common.filter')}
        </Button>
        <Button variant="outline" onClick={handleReset} disabled={loading}>
          {t('common.reset')}
        </Button>
      </div>
    </div>
  );
}
