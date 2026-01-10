"use client"

import * as React from "react"
import { DayPicker } from "react-day-picker"
import { zhCN, enUS } from "date-fns/locale"
import { ChevronLeft, ChevronRight } from "lucide-react"

import { cn } from "@/lib/utils/utils"
import { buttonVariants } from "@/components/ui/button"
import { useLanguage } from "@/contexts/LanguageContext"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

function Calendar({
  className,
  classNames,
  showOutsideDays = true,
  ...props
}: React.ComponentProps<typeof DayPicker>) {
  const { language } = useLanguage()
  
  const locale = language === 'zh' ? zhCN : enUS
  
  const years = Array.from({ length: 100 }, (_, i) => new Date().getFullYear() - 50 + i)
  const months = Array.from({ length: 12 }, (_, i) => i)
  
  const formatMonth = (month: number) => {
    const date = new Date(new Date().getFullYear(), month, 1)
    return date.toLocaleDateString(language === 'zh' ? 'zh-CN' : 'en-US', { month: 'long' })
  }
  
  return (
    <DayPicker
      locale={locale}
      showOutsideDays={showOutsideDays}
      className={cn(
        "p-3",
        className
      )}
      components={{
        Nav: () => <></>,
        MonthCaption: ({ calendarMonth }) => {
          const displayMonth = calendarMonth.date
          const [yearOpen, setYearOpen] = React.useState(false)
          const [monthOpen, setMonthOpen] = React.useState(false)
          
          return (
            <div className="flex items-center justify-between px-1 py-2">
              <button
                onClick={() => {
                  const newDate = new Date(displayMonth)
                  newDate.setMonth(newDate.getMonth() - 1)
                  props.onMonthChange?.(newDate)
                }}
                className={cn(
                  buttonVariants({ variant: "outline" }),
                  "h-8 w-8 p-0 bg-transparent hover:bg-accent"
                )}
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              
              <div className="flex items-center gap-2">
                <Select
                  open={yearOpen}
                  onOpenChange={setYearOpen}
                  value={displayMonth.getFullYear().toString()}
                  onValueChange={(value) => {
                    const newDate = new Date(displayMonth)
                    newDate.setFullYear(parseInt(value))
                    props.onMonthChange?.(newDate)
                  }}
                >
                  <SelectTrigger className="h-8 w-24 px-2 text-sm font-medium border-none bg-transparent hover:bg-accent focus:ring-0">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {years.map(year => (
                      <SelectItem key={year} value={year.toString()}>{year}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select
                  open={monthOpen}
                  onOpenChange={setMonthOpen}
                  value={displayMonth.getMonth().toString()}
                  onValueChange={(value) => {
                    const newDate = new Date(displayMonth)
                    newDate.setMonth(parseInt(value))
                    props.onMonthChange?.(newDate)
                  }}
                >
                  <SelectTrigger className="h-8 w-28 px-2 text-sm font-medium border-none bg-transparent hover:bg-accent focus:ring-0">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {months.map(month => (
                      <SelectItem key={month} value={month.toString()}>{formatMonth(month)}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              
              <button
                onClick={() => {
                  const newDate = new Date(displayMonth)
                  newDate.setMonth(newDate.getMonth() + 1)
                  props.onMonthChange?.(newDate)
                }}
                className={cn(
                  buttonVariants({ variant: "outline" }),
                  "h-8 w-8 p-0 bg-transparent hover:bg-accent"
                )}
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          )
        }
      }}
      classNames={{
        root: "relative",
        months: "flex flex-col sm:flex-row space-y-4 sm:space-x-4 sm:space-y-0",
        month: "space-y-2",
        month_caption: "relative items-center",
        caption_label: "text-sm font-medium",
        month_grid: "w-full border-collapse",
        weekdays: "",
        weekday: "text-muted-foreground rounded-md w-9 font-normal text-[0.8rem]",
        week: "",
        day: "h-9 w-9 text-center text-sm p-0 relative focus-within:relative focus-within:z-20",
        day_button: cn(
          buttonVariants({ variant: "ghost" }),
          "h-9 w-9 p-0 font-normal"
        ),
        selected:
          "bg-primary text-primary-foreground hover:bg-primary hover:text-primary-foreground focus:bg-primary focus:text-primary-foreground",
        range_start: "rounded-l-md",
        range_end: "rounded-r-md",
        range_middle: "bg-accent text-accent-foreground",
        today: "bg-accent text-accent-foreground",
        outside: "text-muted-foreground opacity-50",
        disabled: "text-muted-foreground opacity-50",
        hidden: "invisible",
        ...classNames,
      }}
      {...props}
    />
  )
}
Calendar.displayName = "Calendar"

export { Calendar }
