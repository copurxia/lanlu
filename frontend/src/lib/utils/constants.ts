import {
  BookOpen,
  Tag,
  Calendar,
  Search,
  Clock,
  Star,
  Filter,
  LucideIcon
} from 'lucide-react';

// 图标选项
export interface IconOption {
  value: string;
  label: string;
  icon: LucideIcon;
}

export const ICON_OPTIONS: IconOption[] = [
  { value: 'BookOpen', label: 'BookOpen', icon: BookOpen },
  { value: 'Tag', label: 'Tag', icon: Tag },
  { value: 'Calendar', label: 'Calendar', icon: Calendar },
  { value: 'Search', label: 'Search', icon: Search },
  { value: 'Clock', label: 'Clock', icon: Clock },
  { value: 'Star', label: 'Star', icon: Star },
  { value: 'Filter', label: 'Filter', icon: Filter },
];

// 排序选项
export interface SortOption {
  value: string;
  label: string;
}

export const DEFAULT_SEARCH_SORT_BY = 'created_at';

export type HomeViewMode = 'category-rows' | 'masonry' | 'list' | 'tweet';

export const DEFAULT_HOME_VIEW_MODE: HomeViewMode = 'category-rows';
export const HOME_VIEW_MODE_STORAGE_KEY = 'home_view_mode';

export function normalizeSearchSortBy(value?: string | null, fallback: string = DEFAULT_SEARCH_SORT_BY): string {
  const normalized = String(value || '').trim();
  if (!normalized) return fallback;
  return normalized === 'date_added' ? DEFAULT_SEARCH_SORT_BY : normalized;
}

export function normalizeHomeViewMode(
  value?: string | null,
  fallback: HomeViewMode = DEFAULT_HOME_VIEW_MODE
): HomeViewMode {
  if (value === 'category-rows' || value === 'masonry' || value === 'list' || value === 'tweet') {
    return value;
  }
  return fallback;
}

export const SORT_BY_OPTIONS: SortOption[] = [
  { value: '_default', label: 'default' },
  { value: 'created_at', label: 'createdAt' },
  { value: 'release_at', label: 'releaseAt' },
  { value: 'updated_at', label: 'updatedAt' },
  { value: 'lastread', label: 'lastRead' },
  { value: 'title', label: 'title' },
  { value: 'pagecount', label: 'pageCount' },
];

// 根据 value 获取图标组件
export function getIconByValue(value: string): LucideIcon {
  const option = ICON_OPTIONS.find(opt => opt.value === value);
  return option?.icon || BookOpen;
}
