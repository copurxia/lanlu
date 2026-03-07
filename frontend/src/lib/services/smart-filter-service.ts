import { apiClient } from '@/lib/api';

export interface SmartFilter {
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
  enabled?: boolean;
  sort_order_num?: number;
}

export class SmartFilterService {
  static async getPublicFilters(): Promise<SmartFilter[]> {
    try {
      const response = await apiClient.get('/api/smart_filters');
      const items = response.data?.data?.items || [];
      return items.filter((item: SmartFilter) => item.enabled !== false);
    } catch {
      return [];
    }
  }
}

export function getSmartFilterName(filter: SmartFilter, language: string): string {
  if (language !== 'zh' && filter.translations?.[language]?.text) {
    return filter.translations[language].text || filter.name;
  }

  return filter.name;
}

export function resolveSmartFilterDate(value: string): string {
  const normalizedValue = String(value || '').trim();
  if (!normalizedValue) return '';

  const relativeDays = Number.parseInt(normalizedValue, 10);
  if (!Number.isNaN(relativeDays) && String(relativeDays) === normalizedValue) {
    const date = new Date();
    date.setDate(date.getDate() + relativeDays);
    return date.toISOString().split('T')[0] || '';
  }

  return normalizedValue;
}

export function buildSmartFilterHref(filter: SmartFilter): string {
  const params = new URLSearchParams();

  if (filter.query?.trim()) params.set('q', filter.query.trim());
  if (filter.sort_by?.trim() && filter.sort_by !== '_default') {
    params.set('sortby', filter.sort_by.trim());
  }
  if (filter.sort_order?.trim() && filter.sort_order !== 'desc') {
    params.set('order', filter.sort_order.trim());
  }

  const dateFrom = resolveSmartFilterDate(filter.date_from);
  const dateTo = resolveSmartFilterDate(filter.date_to);
  if (dateFrom) params.set('date_from', dateFrom);
  if (dateTo) params.set('date_to', dateTo);
  if (filter.newonly) params.set('newonly', 'true');
  if (filter.untaggedonly) params.set('untaggedonly', 'true');
  params.set('groupby_tanks', 'true');

  const queryString = params.toString();
  return queryString ? `/?${queryString}` : '/';
}
