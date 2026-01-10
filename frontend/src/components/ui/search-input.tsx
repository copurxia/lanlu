"use client"

import * as React from "react"
import { createPortal } from "react-dom"
import { cn } from "@/lib/utils/utils"
import { Input } from "@/components/ui/input"
import { TagService } from "@/lib/services/tag-service"
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
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = React.useState(false)
  // 添加处理标志以避免重复补全
  const isProcessingRef = React.useRef(false)

  // 设置mounted状态
  React.useEffect(() => {
    setMounted(true)
  }, [])

  // 同步外部传入的 value 到内部 inputValue
  React.useEffect(() => {
    if (value !== inputValue) {
      setInputValue(value)
    }
  }, [value, inputValue])

  // 计算下拉框位置
  const updateDropdownPosition = React.useCallback(() => {
    if (containerRef.current && typeof window !== 'undefined') {
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
      setSuggestions(results)
      setShowSuggestions(results.length > 0)
      setSelectedIndex(-1)
      updateDropdownPosition()
    } catch (error) {
      console.error('自动补全搜索失败:', error)
      setSuggestions([])
      setShowSuggestions(false)
    } finally {
      setLoading(false)
    }
  }, [language, updateDropdownPosition])

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
    if (!showSuggestions || !mounted) return

    const handleScroll = () => updateDropdownPosition()
    const handleResize = () => updateDropdownPosition()

    if (typeof window !== 'undefined') {
      window.addEventListener('scroll', handleScroll, true)
      window.addEventListener('resize', handleResize)
    }

    return () => {
      if (typeof window !== 'undefined') {
        window.removeEventListener('scroll', handleScroll, true)
        window.removeEventListener('resize', handleResize)
      }
    }
  }, [showSuggestions, updateDropdownPosition, mounted])

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value
    setInputValue(newValue)
    onChange(newValue)
    // 获取最后一个词用于自动补全
    const words = newValue.split(/\s+/).filter(w => w.trim())
    const lastWord = words[words.length - 1] || ""
    debouncedFetch(lastWord)
  }

  const handleSelectSuggestion = (suggestion: TagSuggestion) => {
    // 防止重复处理
    if (isProcessingRef.current) return
    isProcessingRef.current = true

    try {
      // 获取当前输入值
      let currentValue = inputValue

      // 移除所有末尾的+号、空格和制表符
      currentValue = currentValue.replace(/[+\s\t]+$/g, '')

      // 使用 namespace:value 格式
      const formattedValue = suggestion.value

      // 将输入值分割成单词
      const words = currentValue.trim().split(/\s+/).filter(w => w.trim())

      if (words.length > 0) {
        // 替换最后一个词
        words[words.length - 1] = formattedValue
      } else {
        // 如果没有词，则直接添加
        words.push(formattedValue)
      }

      // 组合新值
      const newValue = words.join(' ')

      // 更新本地状态
      setInputValue(newValue)
      // 通知父组件
      onChange(newValue)

      setSuggestions([])
      setShowSuggestions(false)
      setSelectedIndex(-1)
      inputRef.current?.focus()
    } finally {
      // 确保处理标志被重置
      setTimeout(() => {
        isProcessingRef.current = false
      }, 0)
    }
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
      if (e.key === "Enter") {
        if (selectedIndex >= 0) {
          e.preventDefault()
          handleSelectSuggestion(suggestions[selectedIndex])
        }
        // 如果没有选中建议，则让回车键继续传播（用于表单提交）
        return
      }
      if (e.key === "Escape") {
        e.preventDefault()
        setShowSuggestions(false)
        setSelectedIndex(-1)
        return
      }
    }
  }

  const handleInputBlur = () => {
    if (!mounted) return
    // 延迟关闭建议列表，以便点击事件能够触发
    setTimeout(() => {
      setShowSuggestions(false)
    }, 200)
  }

  const handleInputFocus = () => {
    if (!mounted) return
    if (inputValue && suggestions.length > 0) {
      updateDropdownPosition()
      setShowSuggestions(true)
    }
  }

  // 滚动选中项到可见区域
  React.useEffect(() => {
    if (!mounted) return
    if (selectedIndex >= 0 && suggestionsRef.current) {
      const selectedElement = suggestionsRef.current.children[selectedIndex] as HTMLElement
      if (selectedElement) {
        selectedElement.scrollIntoView({ block: 'nearest' })
      }
    }
  }, [selectedIndex, mounted])

  // 下拉框内容
  const dropdownContent = mounted && showSuggestions && suggestions.length > 0 && (
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

      {/* 使用 Portal 将下拉框渲染到 body，避免被父容器 overflow 裁剪 */}
      {mounted && typeof document !== 'undefined' && createPortal(dropdownContent, document.body)}

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
