'use client';

import { Button } from '@/components/ui/button';
import { Languages } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

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
