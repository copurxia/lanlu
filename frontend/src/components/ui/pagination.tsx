'use client';

import { Button } from "@/components/ui/button"
import { ChevronLeft, ChevronRight } from "lucide-react"
import { useLanguage } from "@/contexts/LanguageContext"
import { cn } from "@/lib/utils/utils"

interface PaginationProps {
  currentPage: number
  totalPages: number
  onPageChange: (page: number) => void
  className?: string
}

export function Pagination({
  currentPage,
  totalPages,
  onPageChange,
  className = ""
}: PaginationProps) {
  const { t } = useLanguage();
  const pages = []
  // 在移动端显示更少的页码
  const maxVisiblePages = typeof window !== 'undefined' && window.innerWidth < 768 ? 3 : 5
  
  let startPage = Math.max(0, currentPage - Math.floor(maxVisiblePages / 2))
  const endPage = Math.min(totalPages - 1, startPage + maxVisiblePages - 1)
  
  if (endPage - startPage < maxVisiblePages - 1) {
    startPage = Math.max(0, endPage - maxVisiblePages + 1)
  }
  
  for (let i = startPage; i <= endPage; i++) {
    pages.push(i)
  }

  return (
    <div
      className={cn(
        // Keep defaults minimal; callers can add padding via `className`.
        "flex items-center justify-center space-x-1 sm:space-x-2 overflow-x-auto py-0",
        className
      )}
    >
      <Button
        variant="outline"
        size="sm"
        onClick={() => onPageChange(0)}
        disabled={currentPage === 0}
        className="hidden sm:inline-flex"
      >
        {t('common.firstPage')}
      </Button>
      
      <Button
        variant="outline"
        size="sm"
        onClick={() => onPageChange(currentPage - 1)}
        disabled={currentPage === 0}
      >
        <ChevronLeft className="w-4 h-4" />
      </Button>
      
      {startPage > 0 && (
        <>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onPageChange(0)}
            className={currentPage === 0 ? "bg-primary text-primary-foreground" : ""}
          >
            1
          </Button>
          {startPage > 1 && <span className="px-2">...</span>}
        </>
      )}
      
      {pages.map((page) => (
        <Button
          key={page}
          variant="outline"
          size="sm"
          onClick={() => onPageChange(page)}
          className={currentPage === page ? "bg-primary text-primary-foreground" : ""}
        >
          {page + 1}
        </Button>
      ))}
      
      {endPage < totalPages - 1 && (
        <>
          {endPage < totalPages - 2 && <span className="px-2">...</span>}
          <Button
            variant="outline"
            size="sm"
            onClick={() => onPageChange(totalPages - 1)}
            className={currentPage === totalPages - 1 ? "bg-primary text-primary-foreground" : ""}
          >
            {totalPages}
          </Button>
        </>
      )}
      
      <Button
        variant="outline"
        size="sm"
        onClick={() => onPageChange(currentPage + 1)}
        disabled={currentPage === totalPages - 1}
      >
        <ChevronRight className="w-4 h-4" />
      </Button>
      
      <Button
        variant="outline"
        size="sm"
        onClick={() => onPageChange(totalPages - 1)}
        disabled={currentPage === totalPages - 1}
        className="hidden sm:inline-flex"
      >
        {t('common.lastPage')}
      </Button>
    </div>
  )
}
