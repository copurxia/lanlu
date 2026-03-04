'use client';

import { ExternalLink } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { stripNamespace } from '@/lib/utils/tag-utils';
import { cn } from '@/lib/utils/utils';

interface ArchiveSearchTagBadgeProps {
  displayFullTag: string;
  canonicalFullTag?: string;
  onClick: () => void;
  className?: string;
}

export function ArchiveSearchTagBadge({
  displayFullTag,
  canonicalFullTag,
  onClick,
  className,
}: ArchiveSearchTagBadgeProps) {
  const canonical = canonicalFullTag || displayFullTag;
  const colonIdx = canonical.indexOf(':');
  const namespace = colonIdx > 0 ? canonical.slice(0, colonIdx).trim().toLowerCase() : '';
  const isSource = namespace === 'source';
  const sourceValue = isSource ? stripNamespace(canonical).trim() : '';
  const sourceUrl = isSource ? (sourceValue.startsWith('http') ? sourceValue : `https://${sourceValue}`) : '';

  return (
    <Badge
      variant="secondary"
      className={cn('cursor-pointer max-w-full', className)}
      title={displayFullTag}
      onClick={onClick}
    >
      <span className="flex items-center gap-1 max-w-full">
        <span className="truncate">{stripNamespace(displayFullTag)}</span>
        {isSource && sourceValue && (
          <a
            href={sourceUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-primary transition-colors shrink-0"
            title={sourceUrl}
            onClick={(e) => e.stopPropagation()}
          >
            <ExternalLink className="w-3.5 h-3.5" />
          </a>
        )}
      </span>
    </Badge>
  );
}
