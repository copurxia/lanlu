'use client';

import * as React from 'react';
import { type DateRange } from 'react-day-picker';
import { Calendar as CalendarIcon, X } from 'lucide-react';

import { Button, buttonVariants } from '@/components/ui/button';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Dialog, DialogBody, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
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
  const [drawerOpen, setDrawerOpen] = React.useState(false);
  const [isMobile, setIsMobile] = React.useState(false);
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

  React.useEffect(() => {
    if (typeof window === 'undefined') return;
    const mql = window.matchMedia('(max-width: 639px)');
    const onMediaChange = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    setIsMobile(mql.matches);
    mql.addEventListener('change', onMediaChange);
    return () => mql.removeEventListener('change', onMediaChange);
  }, []);

  const [draftRange, setDraftRange] = React.useState<DateRange | undefined>(range);
  React.useEffect(() => {
    if (!drawerOpen) return;
    setDraftRange(range);
  }, [drawerOpen, range]);

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

  const triggerButton = (
    <button
      type="button"
      aria-label={ariaLabel}
      title={ariaLabel}
      onClick={() => (isMobile ? setDrawerOpen(true) : setOpen(true))}
      className={cn(buttonVariants({ variant: 'outline' }), 'w-full justify-start font-normal pr-14')}
    >
      <span className={cn('min-w-0 truncate', !range?.from && 'text-muted-foreground')}>{labelText}</span>
    </button>
  );

  const trigger = (
    <div className={cn('relative w-full', className)}>
      {triggerButton}

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
            setOpen(false);
            setDrawerOpen(false);
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
  );

  if (isMobile) {
    return (
      <>
        {trigger}
        <Dialog open={drawerOpen} onOpenChange={setDrawerOpen}>
          <DialogContent className="w-full">
            <DialogHeader className="px-4 py-3 border-b">
              <DialogTitle className="text-center">{t('search.dateRange')}</DialogTitle>
            </DialogHeader>
            <DialogBody className="px-4 py-4">
              <div className="flex flex-col gap-3">
                <Calendar
                  mode="range"
                  defaultMonth={draftRange?.from}
                  selected={draftRange}
                  onSelect={(next) => setDraftRange(next)}
                  numberOfMonths={1}
                  initialFocus
                  className="rounded-lg border shadow-sm"
                />

                <div className="flex gap-2">
                  <Button
                    type="button"
                    variant="outline"
                    className="flex-1"
                    onClick={() => {
                      onChange({ from: '', to: '' });
                      setDrawerOpen(false);
                    }}
                  >
                    {t('common.reset')}
                  </Button>
                  <Button
                    type="button"
                    className="flex-1"
                    onClick={() => {
                      onChange({
                        from: draftRange?.from ? toYmd(draftRange.from) : '',
                        to: draftRange?.to ? toYmd(draftRange.to) : '',
                      });
                      setDrawerOpen(false);
                    }}
                  >
                    {t('common.confirm')}
                  </Button>
                </div>
              </div>
            </DialogBody>
          </DialogContent>
        </Dialog>
      </>
    );
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <div className={cn('relative w-full', className)}>
        <PopoverTrigger asChild>{triggerButton}</PopoverTrigger>

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
              setOpen(false);
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
