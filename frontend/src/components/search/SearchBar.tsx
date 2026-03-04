'use client';

import React, { useState, useEffect, Suspense } from 'react';
import { Button } from '@/components/ui/button';
import { SearchInput, type SearchInputHandle } from '@/components/ui/search-input';
import { Search } from 'lucide-react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useLanguage } from '@/contexts/LanguageContext';

export type SearchBarHandle = {
  focus: () => void;
};

type SearchBarProps = {
  autoFocus?: boolean;
  onSubmitted?: () => void;
  compact?: boolean;
};

function SearchBarContent(
  { autoFocus, onSubmitted, compact = true }: SearchBarProps,
  ref: React.Ref<SearchBarHandle>
) {
  const { t } = useLanguage();
  const searchParams = useSearchParams();
  const router = useRouter();
  const [query, setQuery] = useState('');
  const searchInputRef = React.useRef<SearchInputHandle>(null);
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = React.useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!mounted) return;
    const urlQuery = searchParams?.get('q');
    setQuery(urlQuery || '');
  }, [searchParams, mounted]);

  useEffect(() => {
    if (!mounted) return;
    if (!autoFocus) return;
    // Defer focus to after the component is in the tree.
    const id = window.setTimeout(() => searchInputRef.current?.focus?.(), 0);
    return () => window.clearTimeout(id);
  }, [autoFocus, mounted]);

  React.useImperativeHandle(
    ref,
    () => ({
      focus: () => searchInputRef.current?.focus?.(),
    }),
    []
  );

  const handleSubmit = (e: React.FormEvent) => {
    if (!mounted) return;
    e.preventDefault();

    // 从 SearchInput 获取当前输入值
    const currentInputValue = searchInputRef.current?.getInputValue?.() || '';

    // 使用当前输入值，如果为空则使用状态中的query
    const searchQuery = currentInputValue.trim() || query.trim();

    // Keep existing filter params when searching so global search works together with filters.
    const params = new URLSearchParams(searchParams?.toString() || '');
    if (searchQuery) {
      params.set('q', searchQuery);
    } else {
      params.delete('q');
      // Relevance sorting only makes sense with a query.
      if (params.get('sortby') === 'relevance') params.delete('sortby');
    }

    const queryString = params.toString();
    router.push(queryString ? `/?${queryString}` : '/');

    onSubmitted?.();
  };

  return (
    <form onSubmit={handleSubmit} className="w-full">
      <div className="flex gap-2 items-center w-full">
        <div className="flex-1 min-w-0">
          <SearchInput
            ref={searchInputRef}
            placeholder={t('search.placeholder')}
            value={query}
            onChange={setQuery}
            compact={compact}
            className="w-full"
          />
        </div>
        <Button
          type="submit"
          size="icon"
          className={compact ? 'flex-shrink-0 h-8 w-8' : 'flex-shrink-0 h-10 w-10'}
        >
          <Search className="w-4 h-4" />
        </Button>
      </div>
    </form>
  );
}

const SearchBarContentWithRef = React.forwardRef<SearchBarHandle, SearchBarProps>(SearchBarContent);

export const SearchBar = React.forwardRef<SearchBarHandle, SearchBarProps>((props, ref) => {
  return (
    <Suspense fallback={
      <form className="w-full">
        <div className="flex gap-2 items-center w-full">
          <div className="flex-1 min-w-0 h-[32px] rounded-md border border-input bg-background px-2 py-1 text-sm" />
          <Button type="button" size="icon" disabled className="flex-shrink-0 h-[32px] w-[32px]">
            <Search className="w-4 h-4" />
          </Button>
        </div>
      </form>
    }>
      <SearchBarContentWithRef ref={ref} {...props} />
    </Suspense>
  );
});

SearchBar.displayName = 'SearchBar';
