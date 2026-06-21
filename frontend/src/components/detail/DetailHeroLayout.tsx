'use client';

import Image from 'next/image';
import { cn } from '@/lib/utils/utils';
import type { ReactNode } from 'react';

type DetailHeroLayoutProps = {
  cover: ReactNode;
  badges?: ReactNode;
  title: ReactNode;
  meta?: ReactNode;
  description?: ReactNode;
  tags?: ReactNode;
  actions?: ReactNode;
  /** URL for the clearlogo shown above the title (prototype pattern) */
  clearlogoUrl?: string;
  clearlogoAlt?: string;
  className?: string;
};

export function DetailHeroLayout({
  cover,
  badges,
  title,
  meta,
  description,
  tags,
  actions,
  clearlogoUrl,
  clearlogoAlt,
  className,
}: DetailHeroLayoutProps) {
  const bodyContent = (
    <>
      {badges ? <div className="flex flex-wrap items-center gap-2">{badges}</div> : null}

      {clearlogoUrl ? (
        <Image
          src={clearlogoUrl}
          alt={clearlogoAlt || (typeof title === 'string' ? title : '') || ''}
          width={360}
          height={72}
          className="mt-4 mb-1 max-h-[72px] w-auto max-w-[min(360px,100%)] object-contain object-left drop-shadow-[0_14px_22px_rgba(0,0,0,0.42)]"
          unoptimized
        />
      ) : null}

      <h1 className="mt-3 text-2xl font-bold tracking-tight wrap-break-word sm:text-3xl lg:text-4xl">
        {title}
      </h1>

      {meta ? <div className="mt-2">{meta}</div> : null}
      {description || tags ? (
        <div className="mt-4 hidden sm:block">
          {description ? (
            <p className="text-sm text-muted-foreground max-w-3xl line-clamp-3">{description}</p>
          ) : null}
          {tags ? <div className="mt-3">{tags}</div> : null}
        </div>
      ) : null}
    </>
  );

  return (
    <section className={cn('detail-hero-grid', className)}>
      <div className="relative aspect-[2/3] w-full overflow-hidden rounded-2xl border border-border/60 bg-muted shadow-lg">
        {cover}
      </div>

      <div className="min-w-0 pb-1">{bodyContent}</div>

      {actions ? (
        <aside className="self-center">{actions}</aside>
      ) : null}

      {/* Mobile: summary and tags span full width */}
      <div className="col-span-full sm:hidden">
        {description ? (
          <p className="text-sm text-muted-foreground max-w-3xl line-clamp-3">{description}</p>
        ) : null}
        {tags ? <div className="mt-3">{tags}</div> : null}
      </div>
    </section>
  );
}
