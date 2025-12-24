'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import zhMessages from '../../messages/zh.json';
import enMessages from '../../messages/en.json';

type Language = 'zh' | 'en';

interface LanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: string) => string;
  messages: any;
}

const messages = {
  zh: zhMessages,
  en: enMessages,
};

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

export function LanguageProvider({ children }: { children: ReactNode }) {
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = useState(false);
  // 使用函数初始化状态，避免在 effect 中调用 setState
  const [language, setLanguage] = useState<Language>('zh');

  useEffect(() => {
    setMounted(true);
  }, []);

  // 只在挂载后从localStorage读取语言设置
  useEffect(() => {
    if (!mounted) return;

    if (typeof window !== 'undefined') {
      // 从 localStorage 读取保存的语言设置
      const savedLanguage = localStorage.getItem('language') as Language;
      if (savedLanguage && (savedLanguage === 'zh' || savedLanguage === 'en')) {
        setLanguage(savedLanguage);
        return;
      }
      // 尝试从浏览器语言检测
      const browserLanguage = navigator.language.toLowerCase();
      if (browserLanguage.startsWith('en')) {
        setLanguage('en');
        return;
      }
    }
    setLanguage('zh');
  }, [mounted]);

  useEffect(() => {
    // 只在客户端执行
    if (!mounted) return;
    if (typeof window !== 'undefined') {
      // 保存语言设置到 localStorage
      localStorage.setItem('language', language);
      // 更新 HTML lang 属性
      document.documentElement.lang = language;

      // 派发自定义事件，通知其他组件语言已改变
      const event = new CustomEvent('languagechange', { detail: language });
      window.dispatchEvent(event);
    }
  }, [language, mounted]);

  const t = (key: string, params?: Record<string, any>): string => {
    const keys = key.split('.');
    let value: any = messages[language];
    
    for (const k of keys) {
      if (value && typeof value === 'object' && k in value) {
        value = value[k];
      } else {
        // 如果在当前语言中找不到，尝试使用默认语言（中文）
        value = messages.zh;
        for (const k of keys) {
          if (value && typeof value === 'object' && k in value) {
            value = value[k];
          } else {
            return key; // 如果都找不到，返回 key 本身
          }
        }
        break;
      }
    }
    
    let result = typeof value === 'string' ? value : key;
    
    // 处理参数插值
    if (params && typeof result === 'string') {
      Object.keys(params).forEach(param => {
        result = result.replace(new RegExp(`{${param}}`, 'g'), String(params[param]));
      });
    }
    
    return result;
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
    const fallbackT = (key: string, params?: Record<string, any>): string => {
      const keys = key.split('.');
      let value: any = zhMessages;

      for (const k of keys) {
        if (value && typeof value === 'object' && k in value) {
          value = value[k];
        } else {
          return key;
        }
      }

      let result = typeof value === 'string' ? value : key;

      if (params && typeof result === 'string') {
        Object.keys(params).forEach(param => {
          result = result.replace(new RegExp(`{${param}}`, 'g'), String(params[param]));
        });
      }

      return result;
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