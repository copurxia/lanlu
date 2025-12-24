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

interface SearchInputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
  compact?: boolean
}

export const SearchInput = React.forwardRef<{ getInputValue?: () => string }, SearchInputProps>(({
  value = "",
  onChange,
  placeholder = "输入搜索关键词或标签",
  className,
  compact = false,
  ...props
}, ref) => {
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

  // 解析当前的搜索词
  const [searchTokens, setSearchTokens] = React.useState<string[]>([])

  React.useEffect(() => {
    // 解析 value 为 tokens（支持空格分隔）
    if (value) {
      const tokens = value.split(/\s+/).filter(t => t.trim())
      setSearchTokens(tokens)
    } else {
      setSearchTokens([])
      setInputValue("")
    }
  }, [value])

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
    if (query.length < 1) {
      setSuggestions([])
      setShowSuggestions(false)
      return
    }

    setLoading(true)
    try {
      const results = await TagService.autocomplete(query, language, 10)
      // 过滤已选择的标签
      const filtered = results.filter(s => !searchTokens.includes(s.display))
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
  }, [language, searchTokens, updateDropdownPosition])

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
    const newInputValue = e.target.value
    setInputValue(newInputValue)
    // 从最后一个 token 获取搜索词
    const tokens = newInputValue.split(/\s+/).filter(t => t.trim())
    const lastToken = tokens[tokens.length - 1] || ""
    debouncedFetch(lastToken)
  }

  const addToken = (token: string) => {
    const newTokens = [...searchTokens, token]
    const newValue = newTokens.join(' ')
    onChange(newValue)
    setInputValue("")
    setSuggestions([])
    setShowSuggestions(false)
    setSelectedIndex(-1)
  }

  const handleSelectSuggestion = (suggestion: TagSuggestion) => {
    addToken(suggestion.label)
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

    if (e.key === "Backspace" && !inputValue && searchTokens.length > 0) {
      // 删除最后一个 token
      const newTokens = searchTokens.slice(0, -1)
      onChange(newTokens.join(' '))
    }
  }

  const removeToken = (tokenToRemove: string) => {
    const newTokens = searchTokens.filter(token => token !== tokenToRemove)
    onChange(newTokens.join(' '))
  }

  const handleInputBlur = () => {
    // 延迟关闭建议列表，以便点击事件能够触发
    setTimeout(() => {
      setShowSuggestions(false)
      // 失焦时不再自动转换为标签，保持输入的文本
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
          <span className="font-medium">{suggestion.label}</span>
          {suggestion.label !== suggestion.value && (
            <span className="ml-2 text-muted-foreground text-xs">
              ({suggestion.value})
            </span>
          )}
        </div>
      ))}
    </div>
  )

  // 暴露方法给父组件
  React.useImperativeHandle(ref, () => ({
    getInputValue: () => inputValue
  }), [inputValue])

  return (
    <div className="relative" ref={containerRef}>
      <div
        className={cn(
          "flex flex-wrap gap-2 items-center w-full rounded-md border border-input bg-background text-sm ring-offset-background focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2",
          compact ? "min-h-[32px] px-2 py-1" : "min-h-[42px] px-3 py-2",
          className
        )}
        onClick={() => inputRef.current?.focus()}
      >
        {searchTokens.map((token) => (
          <Badge
            key={token}
            variant="secondary"
            className={cn(
              "gap-1 pr-1",
              compact ? "h-[22px] text-xs" : "h-6"
            )}
          >
            {token}
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                removeToken(token)
              }}
              className="rounded-sm outline-none ring-offset-background focus:ring-2 focus:ring-ring focus:ring-offset-2"
            >
              <X className={cn("text-muted-foreground hover:text-foreground", compact ? "h-3 w-3" : "h-3 w-3")} />
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
          placeholder={searchTokens.length === 0 ? placeholder : ""}
          className={cn(
            "flex-1 min-w-[80px] border-0 p-0 shadow-none focus-visible:ring-0 focus-visible:ring-offset-0",
            compact ? "h-[24px] text-xs" : "h-auto"
          )}
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
})

SearchInput.displayName = "SearchInput"
