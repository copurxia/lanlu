"use client"

import * as React from "react"
import { cn } from "@/lib/utils/utils"
import { Input } from "@/components/ui/input"
import { Popover, PopoverAnchor, PopoverContent } from "@/components/ui/popover"
import { useAutocomplete, TagSuggestion } from "@/hooks/use-autocomplete"
import { useLanguage } from "@/contexts/LanguageContext"

export type SearchInputHandle = {
  getInputValue: () => string
  focus: () => void
}

interface SearchInputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
  compact?: boolean
}

export const SearchInput = React.forwardRef<SearchInputHandle, SearchInputProps>(({
  value = "",
  onChange,
  placeholder = "输入搜索关键词或标签",
  className,
  compact = false,
  ...props
}, ref) => {
  const { language } = useLanguage()
  const [inputValue, setInputValue] = React.useState("")
  const [mounted, setMounted] = React.useState(false)
  const inputRef = React.useRef<HTMLInputElement>(null)
  const suggestionsRef = React.useRef<HTMLDivElement>(null)
  const isProcessingRef = React.useRef(false)

  const autocomplete = useAutocomplete({ language, maxResults: 10 })

  React.useEffect(() => {
    setMounted(true)
  }, [])

  React.useEffect(() => {
    if (value !== inputValue) {
      setInputValue(value)
    }
  }, [value, inputValue])

  const dropdownOpen = mounted && autocomplete.showSuggestions && autocomplete.suggestions.length > 0

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value
    setInputValue(newValue)
    onChange(newValue)
    const words = newValue.split(/\s+/).filter(w => w.trim())
    const lastWord = words[words.length - 1] || ""
    autocomplete.fetchSuggestions(lastWord)
  }

  const handleSelectSuggestion = (suggestion: TagSuggestion) => {
    if (isProcessingRef.current) return
    isProcessingRef.current = true

    try {
      const currentValue = inputValue.replace(/[+\s\t]+$/g, '')
      const formattedValue = suggestion.value
      const words = currentValue.trim().split(/\s+/).filter(w => w.trim())

      if (words.length > 0) {
        words[words.length - 1] = formattedValue
      } else {
        words.push(formattedValue)
      }

      const newValue = words.join(' ')
      setInputValue(newValue)
      onChange(newValue)
      autocomplete.clearSuggestions()
      inputRef.current?.focus()
    } finally {
      setTimeout(() => { isProcessingRef.current = false }, 0)
    }
  }

  const handleInputKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    autocomplete.handleKeyDown(e, handleSelectSuggestion)
  }

  const handleInputBlur = () => {
    if (!mounted) return
    setTimeout(() => { autocomplete.setShowSuggestions(false) }, 200)
  }

  const handleInputFocus = () => {
    if (!mounted) return
    if (inputValue && autocomplete.suggestions.length > 0) {
      autocomplete.setShowSuggestions(true)
    }
  }

  React.useEffect(() => {
    if (!mounted) return
    if (autocomplete.selectedIndex >= 0 && suggestionsRef.current) {
      const el = suggestionsRef.current.children[autocomplete.selectedIndex] as HTMLElement
      el?.scrollIntoView({ block: 'nearest' })
    }
  }, [autocomplete.selectedIndex, mounted])

  React.useImperativeHandle(
    ref,
    () => ({
      getInputValue: () => inputValue,
      focus: () => inputRef.current?.focus(),
    }),
    [inputValue]
  )

  return (
    <Popover
      open={dropdownOpen}
      onOpenChange={(open) => {
        if (!open) autocomplete.setShowSuggestions(false)
      }}
    >
      <PopoverAnchor asChild>
        <div className="relative">
          <Input
            ref={inputRef}
            value={inputValue}
            onChange={handleInputChange}
            onKeyDown={handleInputKeyDown}
            onBlur={handleInputBlur}
            onFocus={handleInputFocus}
            placeholder={placeholder}
            className={cn(className, compact && "h-8 text-sm")}
            autoComplete="off"
            {...props}
          />
          {autocomplete.loading && inputValue && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
            </div>
          )}
        </div>
      </PopoverAnchor>
      <PopoverContent
        ref={suggestionsRef}
        align="start"
        sideOffset={4}
        onOpenAutoFocus={(e) => e.preventDefault()}
        className="z-9999 w-(--radix-popover-trigger-width) max-h-60 overflow-auto rounded-md border border-input dark:border-input bg-popover dark:bg-popover p-0 shadow-lg backdrop-blur-none"
      >
        {autocomplete.suggestions.map((suggestion, index) => (
          <div
            key={suggestion.value}
            className={cn(
              "px-3 py-2 cursor-pointer text-sm",
              index === autocomplete.selectedIndex
                ? "bg-accent text-accent-foreground"
                : "hover:bg-accent hover:text-accent-foreground"
            )}
            onMouseDown={(e) => { e.preventDefault(); handleSelectSuggestion(suggestion) }}
            onMouseEnter={() => autocomplete.setSelectedIndex(index)}
          >
            <span className="font-medium">{suggestion.label}</span>
            {suggestion.label !== suggestion.value && (
              <span className="ml-2 text-muted-foreground text-xs">({suggestion.value})</span>
            )}
          </div>
        ))}
      </PopoverContent>
    </Popover>
  )
})

SearchInput.displayName = "SearchInput"
