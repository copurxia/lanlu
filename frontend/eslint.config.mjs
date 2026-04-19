import { defineConfig, globalIgnores } from 'eslint/config'
import nextTs from 'eslint-config-next/typescript'
import nextVitals from 'eslint-config-next/core-web-vitals'

const readerLegacyFiles = [
  'src/components/reader/**/*.{ts,tsx}',
  'src/features/reader/**/*.{ts,tsx}',
]

const legacyNoAnyFiles = [
  'src/app/(header)/tankoubon/page.tsx',
  'src/lib/services/archive-service.ts',
  'src/lib/services/chunked-upload-service.ts',
]

const setStateInEffectLegacyFiles = [
  'src/app/(header)/HomePageClient.tsx',
  'src/app/(header)/archive/**/*.{ts,tsx}',
  'src/app/(header)/library/page.tsx',
  'src/app/(header)/settings/**/*.tsx',
  'src/app/(header)/tankoubon/page.tsx',
  'src/app/login/page.tsx',
  'src/components/auth/StepUpDialog.tsx',
  'src/components/cron/ScheduledTaskDialog.tsx',
  'src/components/cron/ScheduledTaskList.tsx',
  'src/components/cron/StartupTaskSettings.tsx',
  'src/components/home/HomeMediaChannel.tsx',
  'src/components/home/useArchivePreviewFeed.ts',
  'src/components/layout/Header.tsx',
  'src/components/layout/HomeViewMenu.tsx',
  'src/components/layout/SearchSidebar.tsx',
  'src/components/search/SearchBar.tsx',
  'src/components/tankoubon/AddToTankoubonDialog.tsx',
  'src/components/tasks/TaskList.tsx',
  'src/components/theme/theme-provider.tsx',
  'src/components/ui/base-media-card-edit-controller.tsx',
  'src/components/ui/date-range-picker.tsx',
  'src/components/ui/dialog.tsx',
  'src/components/ui/unified-menu/hooks/use-media-query.ts',
  'src/contexts/AuthContext.tsx',
  'src/contexts/LanguageContext.tsx',
  'src/contexts/ServerInfoContext.tsx',
  'src/hooks/use-app-back.ts',
  'src/hooks/use-base-media-card-controller.ts',
  'src/hooks/use-grid-row-cover-heights.ts',
  'src/hooks/use-scrollable-card-cover-height.ts',
]

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  globalIgnores(['.next/**', 'out/**', 'build/**', 'next-env.d.ts']),
  {
    linterOptions: {
      reportUnusedDisableDirectives: 'error',
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      'react-hooks/immutability': 'error',
      'react-hooks/set-state-in-effect': 'error',
    },
  },
  {
    files: readerLegacyFiles,
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      'react-hooks/immutability': 'off',
      'react-hooks/set-state-in-effect': 'off',
    },
  },
  {
    files: legacyNoAnyFiles,
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
  {
    files: setStateInEffectLegacyFiles,
    rules: {
      'react-hooks/set-state-in-effect': 'off',
    },
  },
])

export default eslintConfig
