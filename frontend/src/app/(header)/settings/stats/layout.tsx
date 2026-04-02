import { ServerInfoProvider } from '@/contexts/ServerInfoContext';

export default function SettingsStatsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <ServerInfoProvider>{children}</ServerInfoProvider>;
}
