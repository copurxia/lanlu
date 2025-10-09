'use client';

import { Button } from '@/components/ui/button';
import { Languages } from 'lucide-react';
import { useState, useEffect } from 'react';

export function StableLanguageToggle() {
  const [language, setLanguage] = useState<'zh' | 'en'>('zh');

  useEffect(() => {
    // 从 localStorage 读取保存的语言设置
    const savedLanguage = localStorage.getItem('language') as 'zh' | 'en';
    if (savedLanguage && (savedLanguage === 'zh' || savedLanguage === 'en')) {
      setLanguage(savedLanguage);
    } else {
      // 尝试从浏览器语言检测
      const browserLanguage = navigator.language.toLowerCase();
      if (browserLanguage.startsWith('en')) {
        setLanguage('en');
      }
    }
  }, []);

  const toggleLanguage = () => {
    const newLanguage = language === 'zh' ? 'en' : 'zh';
    setLanguage(newLanguage);
    localStorage.setItem('language', newLanguage);
    document.documentElement.lang = newLanguage;
    
    // 强制刷新页面以更新语言
    window.location.reload();
  };

  return (
    <Button
      variant="ghost"
      size="icon"
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        toggleLanguage();
      }}
      className="h-9 w-9 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted"
      title={language === 'zh' ? '切换到英文' : 'Switch to Chinese'}
    >
      <Languages className="h-4 w-4" />
      <span className="sr-only">{language === 'zh' ? '切换到英文' : 'Switch to Chinese'}</span>
    </Button>
  );
}