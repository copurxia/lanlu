"use client"

import * as React from "react"
import { TagService } from "@/lib/services/tag-service"

export interface TagSuggestion {
  value: string;   // 原始标签 (namespace:name)
  label: string;   // 翻译文本
  display: string; // 显示文本 (namespace:翻译文本)
}

export interface UseAutocompleteOptions {
  language: string;
  maxResults?: number;
  debounceMs?: number;
  minQueryLength?: number;
  requireBoundTags?: boolean;
  filterFn?: (suggestion: TagSuggestion) => boolean;
}

export interface UseAutocompleteReturn {
  suggestions: TagSuggestion[];
  loading: boolean;
  showSuggestions: boolean;
  selectedIndex: number;
  setSelectedIndex: React.Dispatch<React.SetStateAction<number>>;
  setShowSuggestions: React.Dispatch<React.SetStateAction<boolean>>;
  fetchSuggestions: (query: string) => void;
  clearSuggestions: () => void;
  handleKeyDown: (e: React.KeyboardEvent, onSelect: (suggestion: TagSuggestion) => void) => boolean;
}

export function useAutocomplete(options: UseAutocompleteOptions): UseAutocompleteReturn {
  const {
    language,
    maxResults = 10,
    debounceMs = 200,
    minQueryLength = 1,
    requireBoundTags = true,
    filterFn,
  } = options;

  const [suggestions, setSuggestions] = React.useState<TagSuggestion[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [showSuggestions, setShowSuggestions] = React.useState(false);
  const [selectedIndex, setSelectedIndex] = React.useState(-1);
  const debounceRef = React.useRef<NodeJS.Timeout | null>(null);

  // 清理防抖
  React.useEffect(() => {
    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
    };
  }, []);

  const doFetch = React.useCallback(async (query: string) => {
    if (query.length < minQueryLength) {
      setSuggestions([]);
      setShowSuggestions(false);
      return;
    }

    setLoading(true);
    try {
      const results = await TagService.autocomplete(query, language, maxResults, requireBoundTags);
      const filtered = filterFn ? results.filter(filterFn) : results;
      setSuggestions(filtered);
      setShowSuggestions(filtered.length > 0);
      setSelectedIndex(-1);
    } catch (error) {
      console.error('自动补全搜索失败:', error);
      setSuggestions([]);
      setShowSuggestions(false);
    } finally {
      setLoading(false);
    }
  }, [language, maxResults, minQueryLength, filterFn]);

  const fetchSuggestions = React.useCallback((query: string) => {
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
    }
    debounceRef.current = setTimeout(() => {
      doFetch(query);
    }, debounceMs);
  }, [doFetch, debounceMs]);

  const clearSuggestions = React.useCallback(() => {
    setSuggestions([]);
    setShowSuggestions(false);
    setSelectedIndex(-1);
  }, []);

  const handleKeyDown = React.useCallback((
    e: React.KeyboardEvent,
    onSelect: (suggestion: TagSuggestion) => void
  ): boolean => {
    if (!showSuggestions || suggestions.length === 0) {
      return false;
    }

    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex(prev => prev < suggestions.length - 1 ? prev + 1 : 0);
      return true;
    }
    if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex(prev => prev > 0 ? prev - 1 : suggestions.length - 1);
      return true;
    }
    if (e.key === "Enter" && selectedIndex >= 0) {
      e.preventDefault();
      onSelect(suggestions[selectedIndex]);
      return true;
    }
    if (e.key === "Escape") {
      e.preventDefault();
      setShowSuggestions(false);
      setSelectedIndex(-1);
      return true;
    }
    return false;
  }, [showSuggestions, suggestions, selectedIndex]);

  return {
    suggestions,
    loading,
    showSuggestions,
    selectedIndex,
    setSelectedIndex,
    setShowSuggestions,
    fetchSuggestions,
    clearSuggestions,
    handleKeyDown,
  };
}
