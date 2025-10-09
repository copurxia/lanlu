'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import zhMessages from '../../messages/zh.json';
import enMessages from '../../messages/en.json';

type Language = 'zh' | 'en';

interface ReaderLanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: string) => string;
}

const messages = {
  zh: zhMessages,
  en: enMessages,
};

const ReaderLanguageContext = createContext<ReaderLanguageContextType | undefined>(undefined);

export function ReaderLanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>('zh');

  useEffect(() => {
    // 从 localStorage 读取保存的语言设置
    const savedLanguage = localStorage.getItem('language') as Language;
    if (savedLanguage && (savedLanguage === 'zh' || savedLanguage === 'en')) {
      setLanguageState(savedLanguage);
    } else {
      // 尝试从浏览器语言检测
      const browserLanguage = navigator.language.toLowerCase();
      if (browserLanguage.startsWith('en')) {
        setLanguageState('en');
      }
    }
  }, []);

  const setLanguage = (lang: Language) => {
    setLanguageState(lang);
    localStorage.setItem('language', lang);
    document.documentElement.lang = lang;
  };

  const t = (key: string): string => {
    const keys = key.split('.');
    let value: any = messages[language];
    
    for (const k of keys) {
      if (value && typeof value === 'object' && k in value) {
        value = value[k];
      } else {
        return key; // 如果找不到翻译，返回原始key
      }
    }
    
    return typeof value === 'string' ? value : key;
  };

  return (
    <ReaderLanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </ReaderLanguageContext.Provider>
  );
}

export function useReaderLanguage() {
  const context = useContext(ReaderLanguageContext);
  if (context === undefined) {
    throw new Error('useReaderLanguage must be used within a ReaderLanguageProvider');
  }
  return context;
}