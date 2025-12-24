"use client"

import * as React from "react"
import { createPortal } from "react-dom"
import { X } from "lucide-react"
import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { TagService } from "@/lib/tag-service"
import { useLanguage } from "@/contexts/LanguageContext"

interface TagSuggestion {
  value: string;   // 原始标签 (namespace:name)
  label: string;   // 翻译文本
  display: string; // 显示文本 (namespace:翻译文本)
}

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
  const [suggestions, setSuggestions] = React.useState<TagSuggestion[]>([])
  const [showSuggestions, setShowSuggestions] = React.useState(false)
  const [selectedIndex, setSelectedIndex] = React.useState(-1)
  const [loading, setLoading] = React.useState(false)
  const [dropdownPosition, setDropdownPosition] = React.useState({ top: 0, left: 0, width: 0 })
  const inputRef = React.useRef<HTMLInputElement>(null)
  const containerRef = React.useRef<HTMLDivElement>(null)
  const suggestionsRef = React.useRef<HTMLDivElement>(null)
  const debounceRef = React.useRef<NodeJS.Timeout | null>(null)

  // 计算下拉框位置
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

  // 搜索自动补全建议
  const fetchSuggestions = React.useCallback(async (query: string) => {
    if (!enableAutocomplete || query.length < 1) {
      setSuggestions([])
      setShowSuggestions(false)
      return
    }

    setLoading(true)
    try {
      const results = await TagService.autocomplete(query, language, 10)
      // 过滤已添加的标签
      const filtered = results.filter(s => !value.includes(s.display))
      setSuggestions(filtered)
      setShowSuggestions(filtered.length > 0)
      setSelectedIndex(-1)
      updateDropdownPosition()
    } catch (error) {
      console.error('自动补全搜索失败:', error)
      setSuggestions([])
      setShowSuggestions(false)
    } finally {
      setLoading(false)
    }
  }, [enableAutocomplete, language, value, updateDropdownPosition])

  // 防抖搜索
  const debouncedFetch = React.useCallback((query: string) => {
    if (debounceRef.current) {
      clearTimeout(debounceRef.current)
    }
    debounceRef.current = setTimeout(() => {
      fetchSuggestions(query)
    }, 200)
  }, [fetchSuggestions])

  // 清理防抖
  React.useEffect(() => {
    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current)
      }
    }
  }, [])

  // 监听滚动和resize事件更新位置
  React.useEffect(() => {
    if (!showSuggestions) return

    const handleScroll = () => updateDropdownPosition()
    const handleResize = () => updateDropdownPosition()

    window.addEventListener('scroll', handleScroll, true)
    window.addEventListener('resize', handleResize)

    return () => {
      window.removeEventListener('scroll', handleScroll, true)
      window.removeEventListener('resize', handleResize)
    }
  }, [showSuggestions, updateDropdownPosition])

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value
    setInputValue(newValue)
    debouncedFetch(newValue)
  }

  const addTag = (tag: string) => {
    const newTag = tag.trim()
    if (newTag && !value.includes(newTag)) {
      onChange([...value, newTag])
    }
    setInputValue("")
    setSuggestions([])
    setShowSuggestions(false)
    setSelectedIndex(-1)
  }

  const handleSelectSuggestion = (suggestion: TagSuggestion) => {
    addTag(suggestion.display)
    inputRef.current?.focus()
  }

  const handleInputKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (showSuggestions && suggestions.length > 0) {
      if (e.key === "ArrowDown") {
        e.preventDefault()
        setSelectedIndex(prev =>
          prev < suggestions.length - 1 ? prev + 1 : 0
        )
        return
      }
      if (e.key === "ArrowUp") {
        e.preventDefault()
        setSelectedIndex(prev =>
          prev > 0 ? prev - 1 : suggestions.length - 1
        )
        return
      }
      if (e.key === "Enter" && selectedIndex >= 0) {
        e.preventDefault()
        handleSelectSuggestion(suggestions[selectedIndex])
        return
      }
      if (e.key === "Escape") {
        e.preventDefault()
        setShowSuggestions(false)
        setSelectedIndex(-1)
        return
      }
    }

    if (e.key === "Enter" || e.key === ",") {
      e.preventDefault()
      addTag(inputValue)
    } else if (e.key === "Backspace" && !inputValue && value.length > 0) {
      // 删除最后一个标签
      onChange(value.slice(0, -1))
    }
  }

  const removeTag = (tagToRemove: string) => {
    onChange(value.filter(tag => tag !== tagToRemove))
  }

  const handleInputBlur = () => {
    // 延迟关闭建议列表，以便点击事件能够触发
    setTimeout(() => {
      setShowSuggestions(false)
      // 失焦时如果有内容，添加为标签
      const newTag = inputValue.trim()
      if (newTag && !value.includes(newTag)) {
        onChange([...value, newTag])
        setInputValue("")
      }
    }, 200)
  }

  const handleInputFocus = () => {
    if (inputValue && suggestions.length > 0) {
      updateDropdownPosition()
      setShowSuggestions(true)
    }
  }

  // 滚动选中项到可见区域
  React.useEffect(() => {
    if (selectedIndex >= 0 && suggestionsRef.current) {
      const selectedElement = suggestionsRef.current.children[selectedIndex] as HTMLElement
      if (selectedElement) {
        selectedElement.scrollIntoView({ block: 'nearest' })
      }
    }
  }, [selectedIndex])

  // 下拉框内容
  const dropdownContent = showSuggestions && suggestions.length > 0 && (
    <div
      ref={suggestionsRef}
      className="fixed z-[9999] max-h-60 overflow-auto rounded-md border border-input bg-popover shadow-lg"
      style={{
        top: dropdownPosition.top,
        left: dropdownPosition.left,
        width: dropdownPosition.width
      }}
    >
      {suggestions.map((suggestion, index) => (
        <div
          key={suggestion.value}
          className={cn(
            "px-3 py-2 cursor-pointer text-sm",
            index === selectedIndex
              ? "bg-accent text-accent-foreground"
              : "hover:bg-accent hover:text-accent-foreground"
          )}
          onMouseDown={(e) => {
            e.preventDefault()
            handleSelectSuggestion(suggestion)
          }}
          onMouseEnter={() => setSelectedIndex(index)}
        >
          <span className="font-medium">{suggestion.display}</span>
          {suggestion.display !== suggestion.value && (
            <span className="ml-2 text-muted-foreground text-xs">
              ({suggestion.value})
            </span>
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
          <Badge
            key={tag}
            variant="secondary"
            className="gap-1 pr-1"
          >
            {tag}
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                removeTag(tag)
              }}
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

      {/* 使用 Portal 将下拉框渲染到 body，避免被父容器 overflow 裁剪 */}
      {typeof document !== 'undefined' && createPortal(dropdownContent, document.body)}

      {/* 加载指示器 */}
      {loading && inputValue && (
        <div className="absolute right-3 top-1/2 -translate-y-1/2">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
        </div>
      )}
    </div>
  )
}
