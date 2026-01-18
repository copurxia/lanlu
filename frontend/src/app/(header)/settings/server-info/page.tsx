import { redirect } from 'next/navigation';

export default function ServerInfoRedirectPage() {
  redirect('/settings/stats');
}

