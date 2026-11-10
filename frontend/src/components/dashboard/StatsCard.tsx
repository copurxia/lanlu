'use client';

import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';

interface StatsCardProps {
  title: string;
  value: number | string;
  icon: React.ReactNode;
  description?: string;
  loading?: boolean;
}

export function StatsCard({ title, value, icon, description, loading = false }: StatsCardProps) {
  if (loading) {
    return (
      <Card>
        <CardContent className="p-6">
          <div className="flex items-center justify-between">
            <Skeleton className="h-4 w-4" />
            <Skeleton className="h-8 w-16" />
          </div>
          <Skeleton className="h-4 w-24 mt-2" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="p-6">
        <div className="flex items-center justify-between">
          <div className="text-muted-foreground">{icon}</div>
          <div className="text-2xl font-bold">{typeof value === 'number' ? value.toLocaleString() : value}</div>
        </div>
        <div className="mt-2">
          <p className="text-sm font-medium text-muted-foreground">{title}</p>
          {description && <p className="text-xs text-muted-foreground mt-1">{description}</p>}
        </div>
      </CardContent>
    </Card>
  );
}
