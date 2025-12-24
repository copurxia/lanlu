'use client';

import { useState, useEffect, Suspense } from 'react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Search } from 'lucide-react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useLanguage } from '@/contexts/LanguageContext';
import { appEvents, AppEvents } from '@/lib/events';

function SearchBarContent() {
  const { t } = useLanguage();
  const searchParams = useSearchParams();
  const router = useRouter();
  const [query, setQuery] = useState('');

  useEffect(() => {
    const urlQuery = searchParams?.get('q');
    if (urlQuery) {
      setQuery(urlQuery);
    }
  }, [searchParams]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim()) {
      router.push(`/?q=${encodeURIComponent(query.trim())}`);
    } else {
      appEvents.emit(AppEvents.SEARCH_RESET);
      router.push('/');
    }
  };

  return (
    <form onSubmit={handleSubmit} className="flex gap-2 w-full max-w-md">
      <Input
        type="text"
        placeholder={t('search.placeholder')}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="flex-1"
      />
      <Button type="submit" size="icon">
        <Search className="w-4 h-4" />
      </Button>
    </form>
  );
}

export function SearchBar() {
  return (
    <Suspense fallback={
      <form className="flex gap-2 w-full max-w-md">
        <Input
          type="text"
          placeholder="搜索..."
          className="flex-1"
          disabled
        />
        <Button type="submit" size="icon" disabled>
          <Search className="w-4 h-4" />
        </Button>
      </form>
    }>
      <SearchBarContent />
    </Suspense>
  );
}