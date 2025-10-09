'use client';

import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Languages } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

export function LanguageToggle() {
  const { language, setLanguage, t } = useLanguage();

  const languages = [
    { code: 'zh', name: '中文' },
    { code: 'en', name: 'English' }
  ];

  const handleLanguageChange = (newLanguage: string) => {
    setLanguage(newLanguage as 'zh' | 'en');
  };

  return (
    <div className="flex items-center space-x-2">
      <Languages className="w-4 h-4" />
      <Select value={language} onValueChange={handleLanguageChange}>
        <SelectTrigger className="w-[120px] h-8">
          <SelectValue placeholder={languages.find(lang => lang.code === language)?.name} />
        </SelectTrigger>
        <SelectContent>
          {languages.map((lang) => (
            <SelectItem key={lang.code} value={lang.code}>
              {lang.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

// 简单的语言切换按钮版本
export function LanguageButton() {
  const { language, setLanguage } = useLanguage();

  const toggleLanguage = () => {
    setLanguage(language === 'zh' ? 'en' : 'zh');
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