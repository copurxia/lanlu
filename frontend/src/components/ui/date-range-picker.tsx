'use client';

import * as React from 'react';
import { type DateRange } from 'react-day-picker';
import { Calendar as CalendarIcon, X } from 'lucide-react';

import { buttonVariants } from '@/components/ui/button';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { useLanguage } from '@/contexts/LanguageContext';
import { cn } from '@/lib/utils/utils';

interface DateRangePickerValue {
  from?: string;
  to?: string;
}

interface DateRangePickerProps {
  value?: DateRangePickerValue;
  onChange: (value: DateRangePickerValue) => void;
  placeholder?: string;
  className?: string;
}

function parseYmd(value?: string): Date | undefined {
  if (!value) return undefined;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) return undefined;
  const date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return undefined;
  return date;
}

function toYmd(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function DateRangePicker({ value, onChange, placeholder, className }: DateRangePickerProps) {
  const { t, language } = useLanguage();
  const ariaLabel = placeholder || t('search.dateRange');
  const [open, setOpen] = React.useState(false);
  const [range, setRange] = React.useState<DateRange | undefined>(() => {
    const from = parseYmd(value?.from);
    const to = parseYmd(value?.to);
    if (!from && !to) return undefined;
    return { from, to };
  });

  React.useEffect(() => {
    const from = parseYmd(value?.from);
    const to = parseYmd(value?.to);
    if (!from && !to) {
      setRange(undefined);
      return;
    }
    setRange({ from, to });
  }, [value?.from, value?.to]);

  const formatDate = (date: Date) => {
    if (language === 'zh') {
      return date.toLocaleDateString('zh-CN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      });
    }
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
  };

  const labelText = (() => {
    if (!range?.from) return ariaLabel;
    if (!range.to) return formatDate(range.from);
    return `${formatDate(range.from)} - ${formatDate(range.to)}`;
  })();

  const hasValue = Boolean(value?.from || value?.to);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <div className={cn('relative w-full', className)}>
        <PopoverTrigger asChild>
          <button
            type="button"
            aria-label={ariaLabel}
            title={ariaLabel}
            className={cn(buttonVariants({ variant: 'outline' }), 'w-full justify-start font-normal pr-14')}
          >
            <span className={cn('min-w-0 truncate', !range?.from && 'text-muted-foreground')}>{labelText}</span>
          </button>
        </PopoverTrigger>

        {hasValue ? (
          <button
            type="button"
            className="absolute right-9 top-1/2 -translate-y-1/2 inline-flex h-7 w-7 items-center justify-center rounded text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            aria-label={t('common.reset')}
            title={t('common.reset')}
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setRange(undefined);
              onChange({ from: '', to: '' });
            }}
          >
            <X className="h-4 w-4" />
          </button>
        ) : null}

        <CalendarIcon
          className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground"
          aria-hidden="true"
        />
      </div>

      <PopoverContent className="w-auto p-0" align="start">
        <Calendar
          mode="range"
          defaultMonth={range?.from}
          selected={range}
          onSelect={(next) => {
            setRange(next);
            onChange({
              from: next?.from ? toYmd(next.from) : '',
              to: next?.to ? toYmd(next.to) : '',
            });
          }}
          numberOfMonths={2}
          initialFocus
          className="rounded-lg border shadow-sm"
        />
      </PopoverContent>
    </Popover>
  );
}
