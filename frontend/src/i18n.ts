import {notFound} from 'next/navigation';
import {getRequestConfig, type RequestConfig} from 'next-intl/server';

// Can be imported from a shared config
const locales = ['en', 'zh'] as const;
type Locale = typeof locales[number];
const defaultLocale: Locale = 'zh';

function isLocale(value: string): value is Locale {
  return locales.includes(value as Locale);
}

export default getRequestConfig(async ({locale, requestLocale}) => {
  const requestedLocale = locale ?? await requestLocale;

  if (requestedLocale !== undefined && !isLocale(requestedLocale)) {
    notFound();
  }

  const resolvedLocale = requestedLocale ?? defaultLocale;

  return {
    locale: resolvedLocale,
    messages: (await import(`../messages/${resolvedLocale}.json`)).default as NonNullable<RequestConfig['messages']>
  };
});
