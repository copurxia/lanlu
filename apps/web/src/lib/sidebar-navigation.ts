import {
  buildSmartFilterHref,
  type SmartFilter,
} from './services/smart-filter-service';

export const SMART_FILTER_PARAM_KEYS = [
  'newonly',
  'untaggedonly',
  'date_from',
  'date_to',
] as const;

type SearchParamsLike = { toString(): string } | null | undefined;

function toParams(searchParams: SearchParamsLike): URLSearchParams {
  return new URLSearchParams(searchParams?.toString() || '');
}

function hrefFromParams(params: URLSearchParams): string {
  const queryString = params.toString();
  return queryString ? `/?${queryString}` : '/';
}

function paramsFromHref(href: string): URLSearchParams {
  const queryIndex = href.indexOf('?');
  return new URLSearchParams(queryIndex >= 0 ? href.slice(queryIndex + 1) : '');
}

export function normalizeSidebarParams(params: URLSearchParams): string {
  const normalized = new URLSearchParams(params.toString());
  normalized.delete('page');
  const entries = Array.from(normalized.entries()).sort(([left], [right]) =>
    left.localeCompare(right)
  );
  return new URLSearchParams(entries).toString();
}

export function hasActiveSmartFilterParams(params: URLSearchParams): boolean {
  return (
    params.get('newonly') === 'true'
    || params.get('newonly') === '1'
    || params.get('untaggedonly') === 'true'
    || params.get('untaggedonly') === '1'
    || Boolean(params.get('date_from')?.trim())
    || Boolean(params.get('date_to')?.trim())
  );
}

export function clearSmartFilterParams(params: URLSearchParams): URLSearchParams {
  const cleared = new URLSearchParams(params.toString());
  for (const key of SMART_FILTER_PARAM_KEYS) cleared.delete(key);
  return cleared;
}

export function buildCategoryHref(
  categoryId: string,
  searchParams: SearchParamsLike,
): string {
  const params = clearSmartFilterParams(toParams(searchParams));
  params.delete('q');
  params.delete('page');
  if (params.get('sortby') === 'relevance') params.delete('sortby');

  if (categoryId === 'all') {
    params.delete('category_id');
  } else {
    params.set('category_id', categoryId);
  }

  return hrefFromParams(params);
}

export function isCategoryActive({
  pathname,
  searchQuery,
  activeCategoryId,
  categoryId,
  searchParams,
}: {
  pathname: string;
  searchQuery: string;
  activeCategoryId: string;
  categoryId: string;
  searchParams: SearchParamsLike;
}): boolean {
  return (
    pathname === '/'
    && !searchQuery
    && activeCategoryId === categoryId
    && !hasActiveSmartFilterParams(toParams(searchParams))
  );
}

export function buildSmartFilterCancelHref(searchParams: SearchParamsLike): string {
  const params = clearSmartFilterParams(toParams(searchParams));
  params.delete('page');
  return hrefFromParams(params);
}

export function isSmartFilterActive(
  filter: SmartFilter,
  searchParams: SearchParamsLike,
  pathname: string,
): boolean {
  if (pathname !== '/') return false;

  const smartHref = buildSmartFilterHref(filter);
  const smartParams = paramsFromHref(smartHref);
  if (!normalizeSidebarParams(smartParams)) {
    return !normalizeSidebarParams(toParams(searchParams));
  }

  const current = toParams(searchParams);
  current.delete('category_id');
  return normalizeSidebarParams(smartParams) === normalizeSidebarParams(current);
}

export function getSmartFilterSidebarState(
  filter: SmartFilter,
  searchParams: SearchParamsLike,
  pathname: string,
): { href: string; isActive: boolean } {
  const isActive = isSmartFilterActive(filter, searchParams, pathname);
  return {
    href: isActive ? buildSmartFilterCancelHref(searchParams) : buildSmartFilterHref(filter),
    isActive,
  };
}
