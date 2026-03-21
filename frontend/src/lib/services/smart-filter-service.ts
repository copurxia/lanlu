import { apiClient } from '@/lib/api';
import { buildQueryParams } from '@/lib/utils/api-utils';

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
  const dateFrom = resolveSmartFilterDate(filter.date_from);
  const dateTo = resolveSmartFilterDate(filter.date_to);
  const params = buildQueryParams({
    q: filter.query?.trim() || undefined,
    sortby: filter.sort_by?.trim() && filter.sort_by !== '_default' ? filter.sort_by.trim() : undefined,
    order: filter.sort_order?.trim() && filter.sort_order !== 'desc' ? filter.sort_order.trim() : undefined,
    date_from: dateFrom || undefined,
    date_to: dateTo || undefined,
    newonly: filter.newonly ? 'true' : undefined,
    untaggedonly: filter.untaggedonly ? 'true' : undefined,
    groupby_tanks: 'true',
  });

  const queryString = params.toString();
  return queryString ? `/?${queryString}` : '/';
}
