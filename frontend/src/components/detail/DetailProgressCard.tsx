'use client';

import { Progress } from '@/components/ui/progress';
import { DetailSectionCard } from './DetailSectionCard';

type DetailProgressCardProps = {
  title: string;
  subtitle?: string;
  progress: number;
  total: number;
  percent: number;
};

export function DetailProgressCard({
  title,
  subtitle,
  progress,
  total,
  percent,
}: DetailProgressCardProps) {
  return (
    <DetailSectionCard title={title} subtitle={subtitle} variant="glass">
      <div className="flex items-end gap-3 mb-3">
        <strong className="text-4xl font-semibold tracking-tight leading-none">
          {percent}%
        </strong>
        <span className="pb-1 text-sm text-muted-foreground">
          {progress} / {total}
        </span>
      </div>
      <Progress className="h-2" value={percent} />
    </DetailSectionCard>
  );
}
