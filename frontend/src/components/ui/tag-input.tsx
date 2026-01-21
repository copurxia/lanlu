"use client"

import * as React from "react"
import { createPortal } from "react-dom"
import { X } from "lucide-react"
import { cn } from "@/lib/utils/utils"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { useAutocomplete, TagSuggestion } from "@/hooks/use-autocomplete"
import { useLanguage } from "@/contexts/LanguageContext"

interface TagInputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> {
  value: string[]
  onChange: (tags: string[]) => void
  placeholder?: string
  className?: string
  enableAutocomplete?: boolean
}

export function TagInput({
  value = [],
  onChange,
  placeholder = "输入标签后按回车添加",
  className,
  enableAutocomplete = true,
  ...props
}: TagInputProps) {
  const { language } = useLanguage()
  const [inputValue, setInputValue] = React.useState("")
  const [dropdownPosition, setDropdownPosition] = React.useState({ top: 0, left: 0, width: 0 })
  const inputRef = React.useRef<HTMLInputElement>(null)
  const containerRef = React.useRef<HTMLDivElement>(null)
  const suggestionsRef = React.useRef<HTMLDivElement>(null)

  const autocomplete = useAutocomplete({
    language,
    maxResults: 10,
    // Archive tag editor needs to suggest all tags, not just those already bound to archives.
    requireBoundTags: false,
    filterFn: enableAutocomplete ? (s) => !value.includes(s.display) : undefined,
  })

  const updateDropdownPosition = React.useCallback(() => {
    if (containerRef.current) {
      const rect = containerRef.current.getBoundingClientRect()
      setDropdownPosition({
        top: rect.bottom + window.scrollY + 4,
        left: rect.left + window.scrollX,
        width: rect.width
      })
    }
  }, [])

  React.useEffect(() => {
    if (!autocomplete.showSuggestions) return
    const handleScroll = () => updateDropdownPosition()
    const handleResize = () => updateDropdownPosition()
    window.addEventListener('scroll', handleScroll, true)
    window.addEventListener('resize', handleResize)
    return () => {
      window.removeEventListener('scroll', handleScroll, true)
      window.removeEventListener('resize', handleResize)
    }
  }, [autocomplete.showSuggestions, updateDropdownPosition])

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value
    setInputValue(newValue)
    if (enableAutocomplete) {
      autocomplete.fetchSuggestions(newValue)
      updateDropdownPosition()
    }
  }

  const addTag = (tag: string) => {
    const newTag = tag.trim()
    if (newTag && !value.includes(newTag)) {
      onChange([...value, newTag])
    }
    setInputValue("")
    autocomplete.clearSuggestions()
  }

  const handleSelectSuggestion = (suggestion: TagSuggestion) => {
    addTag(suggestion.display)
    inputRef.current?.focus()
  }

  const handleInputKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (autocomplete.handleKeyDown(e, handleSelectSuggestion)) return

    if (e.key === "Enter" || e.key === ",") {
      e.preventDefault()
      addTag(inputValue)
    } else if (e.key === "Backspace" && !inputValue && value.length > 0) {
      onChange(value.slice(0, -1))
    }
  }

  const removeTag = (tagToRemove: string) => {
    onChange(value.filter(tag => tag !== tagToRemove))
  }

  const handleInputBlur = () => {
    setTimeout(() => {
      autocomplete.setShowSuggestions(false)
      const newTag = inputValue.trim()
      if (newTag && !value.includes(newTag)) {
        onChange([...value, newTag])
        setInputValue("")
      }
    }, 200)
  }

  const handleInputFocus = () => {
    if (inputValue && autocomplete.suggestions.length > 0) {
      updateDropdownPosition()
      autocomplete.setShowSuggestions(true)
    }
  }

  React.useEffect(() => {
    if (autocomplete.selectedIndex >= 0 && suggestionsRef.current) {
      const el = suggestionsRef.current.children[autocomplete.selectedIndex] as HTMLElement
      el?.scrollIntoView({ block: 'nearest' })
    }
  }, [autocomplete.selectedIndex])

  const dropdownContent = autocomplete.showSuggestions && autocomplete.suggestions.length > 0 && (
    <div
      ref={suggestionsRef}
      className="fixed z-[9999] max-h-60 overflow-auto rounded-md border border-input bg-popover shadow-lg"
      style={{ top: dropdownPosition.top, left: dropdownPosition.left, width: dropdownPosition.width }}
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
          <span className="font-medium">{suggestion.display}</span>
          {suggestion.display !== suggestion.value && (
            <span className="ml-2 text-muted-foreground text-xs">({suggestion.value})</span>
          )}
        </div>
      ))}
    </div>
  )

  return (
    <div className="relative" ref={containerRef}>
      <div
        className={cn(
          "flex flex-wrap gap-2 items-center min-h-[42px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2",
          className
        )}
        onClick={() => inputRef.current?.focus()}
      >
        {value.map((tag) => (
          <Badge key={tag} variant="secondary" className="gap-1 pr-1">
            {tag}
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); removeTag(tag) }}
              className="rounded-sm outline-none ring-offset-background focus:ring-2 focus:ring-ring focus:ring-offset-2"
            >
              <X className="h-3 w-3 text-muted-foreground hover:text-foreground" />
            </button>
          </Badge>
        ))}
        <Input
          ref={inputRef}
          value={inputValue}
          onChange={handleInputChange}
          onKeyDown={handleInputKeyDown}
          onBlur={handleInputBlur}
          onFocus={handleInputFocus}
          placeholder={value.length === 0 ? placeholder : ""}
          className="flex-1 min-w-[80px] h-auto border-0 p-0 shadow-none focus-visible:ring-0 focus-visible:ring-offset-0"
          autoComplete="off"
          {...props}
        />
      </div>
      {typeof document !== 'undefined' && createPortal(dropdownContent, document.body)}
      {autocomplete.loading && inputValue && (
        <div className="absolute right-3 top-1/2 -translate-y-1/2">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
        </div>
      )}
    </div>
  )
}
