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

export const SORT_BY_OPTIONS: SortOption[] = [
  { value: '_default', label: 'default' },
  { value: 'date_added', label: 'dateAdded' },
  { value: 'lastread', label: 'lastRead' },
  { value: 'title', label: 'title' },
  { value: 'pagecount', label: 'pageCount' },
];

// 根据 value 获取图标组件
export function getIconByValue(value: string): LucideIcon {
  const option = ICON_OPTIONS.find(opt => opt.value === value);
  return option?.icon || BookOpen;
}
