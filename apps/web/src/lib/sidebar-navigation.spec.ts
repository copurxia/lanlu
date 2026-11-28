import { describe, expect, it } from 'vitest';

import {
  buildSmartFilterHref,
  type SmartFilter,
} from './services/smart-filter-service';
import {
  SMART_FILTER_PARAM_KEYS,
  buildCategoryHref,
  getSmartFilterSidebarState,
  isCategoryActive,
} from './sidebar-navigation';

function paramsFromHref(href: string): URLSearchParams {
  const queryIndex = href.indexOf('?');
  return new URLSearchParams(queryIndex >= 0 ? href.slice(queryIndex + 1) : '');
}

function smartFilterWithNewonly(): SmartFilter {
  return {
    id: 1,
    name: '未读档案',
    translations: {},
    icon: 'BookOpen',
    query: '',
    sort_by: '_default',
    sort_order: 'desc',
    date_from: '',
    date_to: '',
    newonly: true,
    untaggedonly: false,
  };
}

describe('sidebar navigation', () => {
  it('clears smart-filter params when navigating to a folder or all', () => {
    const source = new URLSearchParams({
      newonly: 'true',
      untaggedonly: 'true',
      date_from: '2026-01-01',
      date_to: '2026-02-01',
      q: 'search',
      page: '3',
      sortby: 'relevance',
      groupby_tanks: 'true',
    });

    const folder = paramsFromHref(buildCategoryHref('42', source));
    expect(folder.get('category_id')).toBe('42');
    expect(folder.get('groupby_tanks')).toBe('true');
    expect(folder.has('q')).toBe(false);
    expect(folder.has('page')).toBe(false);
    expect(folder.has('sortby')).toBe(false);
    for (const key of SMART_FILTER_PARAM_KEYS) {
      expect(folder.has(key)).toBe(false);
    }

    const all = paramsFromHref(
      buildCategoryHref('all', new URLSearchParams('category_id=42&newonly=true')),
    );
    expect(all.has('category_id')).toBe(false);
    expect(all.has('newonly')).toBe(false);
  });

  it('does not mark a category active while smart-filter params remain', () => {
    expect(
      isCategoryActive({
        pathname: '/',
        searchQuery: '',
        activeCategoryId: 'all',
        categoryId: 'all',
        searchParams: new URLSearchParams('groupby_tanks=true'),
      }),
    ).toBe(true);

    for (const [key, value] of [
      ['newonly', 'true'],
      ['untaggedonly', 'true'],
      ['date_from', '2026-01-01'],
      ['date_to', '2026-02-01'],
    ] as const) {
      expect(
        isCategoryActive({
          pathname: '/',
          searchQuery: '',
          activeCategoryId: 'all',
          categoryId: 'all',
          searchParams: new URLSearchParams({ [key]: value }),
        }),
      ).toBe(false);
    }

    expect(
      isCategoryActive({
        pathname: '/',
        searchQuery: '',
        activeCategoryId: '42',
        categoryId: '42',
        searchParams: new URLSearchParams('newonly=true'),
      }),
    ).toBe(false);
  });

  it('turns an active smart filter into a cancellation link while preserving folder state', () => {
    const filter = smartFilterWithNewonly();
    const smartHref = buildSmartFilterHref(filter);
    const current = paramsFromHref(smartHref);
    current.set('category_id', '42');

    const active = getSmartFilterSidebarState(filter, current, '/');
    expect(active.isActive).toBe(true);

    const cancel = paramsFromHref(active.href);
    expect(cancel.get('category_id')).toBe('42');
    expect(cancel.get('groupby_tanks')).toBe('true');
    for (const key of SMART_FILTER_PARAM_KEYS) {
      expect(cancel.has(key)).toBe(false);
    }

    const inactive = getSmartFilterSidebarState(
      filter,
      new URLSearchParams('category_id=42'),
      '/',
    );
    expect(inactive.isActive).toBe(false);
    expect(inactive.href).toBe(smartHref);
  });
});
