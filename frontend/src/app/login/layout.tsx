import { ServerInfoProvider } from '@/contexts/ServerInfoContext';

export default function LoginLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <ServerInfoProvider>{children}</ServerInfoProvider>;
}
