/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  images: {
    unoptimized: true,
  },

  experimental: {
    // inlineCss 在静态导出下会把同一份 CSS 重复内联进 head 与 RSC payload
    // （实测 HTML 中出现 3 份、约 430KB 文本），改回外链 CSS 走 immutable 缓存。
    inlineCss: false,
    optimizePackageImports: [
      'lucide-react',
      '@radix-ui/react-icons',
      '@radix-ui/react-dialog',
      '@radix-ui/react-dropdown-menu',
      '@radix-ui/react-select',
      '@radix-ui/react-popover',
      '@radix-ui/react-tabs',
      '@radix-ui/react-checkbox',
      '@radix-ui/react-switch',
      '@radix-ui/react-avatar',
      '@radix-ui/react-collapsible',
      '@radix-ui/react-separator',
      '@radix-ui/react-slot',
      '@radix-ui/react-toast',
      'date-fns',
      'd3-cloud',
      'recharts',
      'react-day-picker',
    ],
  },
  
  compiler: {
    removeConsole: process.env.NODE_ENV === 'production',
  },
  
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || '',
    NEXT_PUBLIC_API_KEY: process.env.NEXT_PUBLIC_API_KEY || 'comic',
    NEXT_PUBLIC_STATIC_EXPORT: 'true',
  },
  
  reactStrictMode: false,
  skipTrailingSlashRedirect: true,
  generateBuildId: () => 'build',
}

module.exports = nextConfig
