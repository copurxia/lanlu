import { Button } from '@/components/ui/button';
import { ThemeButton } from '@/components/theme/theme-toggle';
import { LanguageButton } from '@/components/language/LanguageButton';
import { ArrowLeft, Menu } from 'lucide-react';
import type { ReactNode } from 'react';

export function ReaderTopBar({
  showToolbar,
  archiveTitle,
  onBack,
  onToggleSidebar,
  onToggleReadingMode,
  readingModeIcon,
  readingModeText,
  t,
}: {
  showToolbar: boolean;
  archiveTitle: string;
  onBack: () => void;
  onToggleSidebar: () => void;
  onToggleReadingMode: () => void;
  readingModeIcon: ReactNode;
  readingModeText: string;
  t: (key: string) => string;
}) {
  return (
    <div
      className={`
        bg-background/95 backdrop-blur-sm border-b
        transition-all duration-250 ease-out
        will-change-transform will-change-opacity
        ${showToolbar ? 'h-auto translate-y-0 opacity-100' : '!h-0 -translate-y-4 opacity-0 overflow-hidden'}
      `}
    >
      <div
        className={`
          transition-all duration-250 ease-out
          ${showToolbar ? 'p-3 opacity-100' : 'p-0 opacity-0'}
        `}
      >
        <div
          className={`flex items-center justify-between transition-all duration-250 ease-out ${
            showToolbar ? 'opacity-100 scale-100' : 'opacity-0 scale-95'
          }`}
        >
          <div
            className={`flex items-center space-x-2 transition-all duration-250 ease-out delay-50 ${
              showToolbar ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-4'
            }`}
          >
            <Button
              variant="outline"
              size="sm"
              className="border-border bg-background hover:bg-accent hover:text-accent-foreground pointer-events-auto relative z-50"
              onClick={onBack}
            >
              <ArrowLeft className="w-4 h-4 mr-2" />
              <span className="hidden sm:inline">{t('reader.back')}</span>
            </Button>

            <ThemeButton />
            <LanguageButton />

            <Button
              variant="ghost"
              size="icon"
              onClick={onToggleSidebar}
              className={`
                transition-all duration-250 ease-out delay-50
                ${showToolbar ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-4 pointer-events-none'}
              `}
              title={t('reader.navigation')}
            >
              <Menu className="w-5 h-5" />
            </Button>
          </div>

          {archiveTitle && (
            <div
              className={`hidden lg:flex items-center justify-center flex-1 px-4 transition-all duration-250 ease-out delay-75 ${
                showToolbar ? 'opacity-100 scale-100' : 'opacity-0 scale-95'
              }`}
            >
              <h1
                className="text-sm font-medium text-foreground truncate max-w-md text-center"
                title={archiveTitle}
              >
                {archiveTitle}
              </h1>
            </div>
          )}

          <Button
            variant="outline"
            size="sm"
            onClick={onToggleReadingMode}
            className={`border-border bg-background hover:bg-accent hover:text-accent-foreground transition-all duration-250 ease-out delay-50 ${
              showToolbar ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-4'
            }`}
          >
            {readingModeIcon}
            <span className="ml-2 hidden sm:inline">{readingModeText}</span>
          </Button>
        </div>
      </div>
    </div>
  );
}

