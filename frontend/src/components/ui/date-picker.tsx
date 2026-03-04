'use client';

import * as React from 'react';
import { Calendar as CalendarIcon, X } from 'lucide-react';
import { buttonVariants } from '@/components/ui/button';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { useLanguage } from '@/contexts/LanguageContext';
import { cn } from '@/lib/utils/utils';

interface DatePickerProps {
  value?: string;
  onChange: (value: string) => void;
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

export function DatePicker({ value, onChange, placeholder, className }: DatePickerProps) {
  const { t, language } = useLanguage();
  const ariaLabel = placeholder || t('common.selectDate');
  const [open, setOpen] = React.useState(false);
  const [date, setDate] = React.useState<Date | undefined>(() => parseYmd(value));

  React.useEffect(() => {
    setDate(parseYmd(value));
  }, [value]);

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

  const setValueFromDate = (selectedDate?: Date) => {
    setDate(selectedDate);
    if (!selectedDate) {
      onChange('');
      return;
    }
    const year = selectedDate.getFullYear();
    const month = String(selectedDate.getMonth() + 1).padStart(2, '0');
    const day = String(selectedDate.getDate()).padStart(2, '0');
    onChange(`${year}-${month}-${day}`);
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <div className={cn('relative w-full', className)}>
        <PopoverTrigger asChild>
          <button
            type="button"
            aria-label={ariaLabel}
            title={ariaLabel}
            className={cn(
              buttonVariants({ variant: 'outline' }),
              'w-full justify-start font-normal pr-14'
            )}
          >
            <span className={cn('min-w-0 truncate', !date && 'text-muted-foreground')}>
              {date ? formatDate(date) : ariaLabel}
            </span>
          </button>
        </PopoverTrigger>

        {value ? (
          <button
            type="button"
            className="absolute right-9 top-1/2 -translate-y-1/2 inline-flex h-7 w-7 items-center justify-center rounded text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            aria-label={t('common.reset')}
            title={t('common.reset')}
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setValueFromDate(undefined);
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

      <PopoverContent className="w-[280px] p-0" align="start">
        <Calendar
          mode="single"
          selected={date}
          onSelect={(d) => {
            setValueFromDate(d);
            setOpen(false);
          }}
          initialFocus
          classNames={{
            months: 'flex flex-col space-y-4',
            caption: 'flex justify-center pt-1 relative items-center',
            table: 'w-full border-collapse space-y-1',
            head_cell: 'text-muted-foreground rounded-md w-9 font-normal text-[0.8rem]',
            cell: 'h-9 w-9 text-center text-sm p-0 relative focus-within:relative focus-within:z-20',
          }}
        />
      </PopoverContent>
    </Popover>
  );
}
