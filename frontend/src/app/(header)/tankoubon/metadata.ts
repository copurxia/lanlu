import type { Metadata } from 'next';
import { headers } from 'next/headers';
import zhMessages from '../../../../messages/zh.json';
import enMessages from '../../../../messages/en.json';

type Locale = 'zh' | 'en';

const fallbackLocale: Locale = 'zh';
const supportedLocales: Locale[] = ['zh', 'en'];

type TankoubonMessages = {
  metaDescription?: string;
  metaKeywords?: string;
  collection?: string;
};

interface LocaleMessages {
  appName?: string;
  tankoubon?: TankoubonMessages;
}

const translations: Record<Locale, LocaleMessages> = {
  zh: zhMessages,
  en: enMessages,
};

const parseAcceptLanguage = (value: string | null): Locale => {
  if (!value) {
    return fallbackLocale;
  }

  const candidates = value
    .split(',')
    .map((entry) => entry.split(';')[0].trim().toLowerCase())
    .filter(Boolean);

  for (const candidate of candidates) {
    if (supportedLocales.includes(candidate as Locale)) {
      return candidate as Locale;
    }

    const primary = candidate.split('-')[0] as Locale;
    if (supportedLocales.includes(primary)) {
      return primary;
    }
  }

  return fallbackLocale;
};

const getLocale = async (): Promise<Locale> => {
  const acceptLanguage = (await headers()).get('accept-language');
  return parseAcceptLanguage(acceptLanguage);
};

export async function generateMetadata(): Promise<Metadata> {
  const locale = await getLocale();
  const localeMessages = translations[locale] ?? translations[fallbackLocale];
  const tankoubonMessages =
    localeMessages.tankoubon ?? translations[fallbackLocale].tankoubon;
  const appName = localeMessages.appName ?? translations[fallbackLocale].appName;
  const description =
    tankoubonMessages?.metaDescription ??
    translations[fallbackLocale].tankoubon?.metaDescription ??
    '';
  const keywords =
    tankoubonMessages?.metaKeywords ??
    translations[fallbackLocale].tankoubon?.metaKeywords ??
    '';
  const title = `${tankoubonMessages?.collection ?? translations[fallbackLocale].tankoubon?.collection} · ${appName}`;

  return {
    title,
    description,
    keywords,
    openGraph: {
      title,
      description,
      url: '/tankoubon',
      type: 'website',
    },
  };
}
