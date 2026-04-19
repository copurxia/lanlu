'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import zhMessages from '../../messages/zh.json';
import enMessages from '../../messages/en.json';

type Language = 'zh' | 'en';
type TranslationParams = Record<string, string | number | boolean | null | undefined>;
type TranslationMessages = { [key: string]: string | TranslationMessages };

interface LanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: string) => string;
  messages: TranslationMessages;
}

const messages: Record<Language, TranslationMessages> = {
  zh: zhMessages as TranslationMessages,
  en: enMessages as TranslationMessages,
};

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

function resolveMessage(source: TranslationMessages, key: string): string | null {
  const keys = key.split('.');
  let current: string | TranslationMessages = source;

  for (const segment of keys) {
    if (typeof current === 'string') {
      return null;
    }

    const next: string | TranslationMessages | undefined = current[segment];
    if (next === undefined) {
      return null;
    }
    current = next;
  }

  return typeof current === 'string' ? current : null;
}

function interpolateMessage(template: string, params?: TranslationParams): string {
  if (!params) {
    return template;
  }

  let result = template;
  Object.keys(params).forEach((param) => {
    result = result.replace(new RegExp(`{${param}}`, 'g'), String(params[param]));
  });
  return result;
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguage] = useState<Language>('zh');

  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    const savedLanguage = localStorage.getItem('language') as Language;
    if (savedLanguage === 'zh' || savedLanguage === 'en') {
      setLanguage((current) => (current === savedLanguage ? current : savedLanguage));
      return;
    }

    const browserLanguage = navigator.language.toLowerCase();
    if (browserLanguage.startsWith('en')) {
      setLanguage('en');
    }
  }, []);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    localStorage.setItem('language', language);
    document.documentElement.lang = language;
    window.dispatchEvent(new CustomEvent('languagechange', { detail: language }));
  }, [language]);

  const t = (key: string, params?: TranslationParams): string => {
    const value = resolveMessage(messages[language], key) ?? resolveMessage(messages.zh, key) ?? key;
    return interpolateMessage(value, params);
  };

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t, messages: messages[language] }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  // 使用 useContext 必须在组件的顶层调用，不能有条件判断
  const context = useContext(LanguageContext);
  
  // 只在服务端静态生成期间返回回退值，避免调用useContext
  // 客户端环境下正常使用 Context，即使是在静态导出模式下
  if (typeof window === 'undefined' && process.env.NEXT_PUBLIC_STATIC_EXPORT === 'true') {
    const fallbackT = (key: string, params?: TranslationParams): string => {
      const value = resolveMessage(messages.zh, key) ?? key;
      return interpolateMessage(value, params);
    };

    return {
      language: 'zh',
      setLanguage: () => {},
      t: fallbackT,
      messages: zhMessages
    };
  }

  if (context === undefined) {
    throw new Error('useLanguage must be used within a LanguageProvider');
  }
  return context;
}
