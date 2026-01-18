"use client"

import * as React from "react"
import { cn } from "@/lib/utils/utils"

interface DialogProps {
  open?: boolean
  onOpenChange?: (open: boolean) => void
  children: React.ReactNode
}

type DialogSize = 'sm' | 'md' | 'lg' | 'xl' | 'fluid'

type DialogContextValue = {
  open: boolean
  onOpenChange?: (open: boolean) => void
}

const DialogContext = React.createContext<DialogContextValue | null>(null)

function useDialogContext() {
  const ctx = React.useContext(DialogContext)
  if (!ctx) throw new Error("Dialog components must be used within <Dialog />")
  return ctx
}

const Dialog: React.FC<DialogProps> = ({ open = false, onOpenChange, children }) => {
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = React.useState(false)

  React.useEffect(() => {
    setMounted(true)
  }, [])

  return (
    <DialogContext.Provider value={{ open: !!open, onOpenChange }}>
      {mounted ? children : null}
    </DialogContext.Provider>
  )
}

const DialogHeader: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn("flex flex-col gap-1.5 text-center sm:text-left px-4 sm:px-6 pt-4 sm:pt-6 pb-4", className)}>
    {children}
  </div>
)

const DialogTitle: React.FC<{ className?: string; children: React.ReactNode }> = ({ 
  className, 
  children 
}) => (
  <h2 className={cn("text-lg font-semibold leading-none tracking-tight", className)}>
    {children}
  </h2>
)

const DialogDescription: React.FC<{ className?: string; children: React.ReactNode }> = ({ 
  className, 
  children 
}) => (
  <p className={cn("text-sm text-muted-foreground", className)}>
    {children}
  </p>
)

const DialogContent: React.FC<{
  className?: string
  children: React.ReactNode
  size?: DialogSize
}> = ({ className, children, size = 'md' }) => {
  const { open, onOpenChange } = useDialogContext()
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = React.useState(false)
  const [isMobile, setIsMobile] = React.useState(false)
  const [present, setPresent] = React.useState(false)
  const [active, setActive] = React.useState(false)

  React.useEffect(() => {
    setMounted(true)
  }, [])

  React.useEffect(() => {
    if (!mounted) return
    const mql = window.matchMedia("(max-width: 639px)")
    const onChange = (e: MediaQueryListEvent) => setIsMobile(e.matches)
    setIsMobile(mql.matches)
    mql.addEventListener("change", onChange)
    return () => mql.removeEventListener("change", onChange)
  }, [mounted])

  // Keep the dialog mounted long enough for open/close animations.
  React.useEffect(() => {
    if (!mounted) return
    if (open) {
      setPresent(true)
      // Activate animation on next frame so transitions run.
      const raf = window.requestAnimationFrame(() => setActive(true))
      return () => window.cancelAnimationFrame(raf)
    }

    if (!present) return
    setActive(false)
    const t = window.setTimeout(() => setPresent(false), 200)
    return () => window.clearTimeout(t)
  }, [mounted, open, present])

  React.useEffect(() => {
    if (!open) return
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onOpenChange?.(false)
    }
    window.addEventListener("keydown", onKeyDown)
    return () => window.removeEventListener("keydown", onKeyDown)
  }, [open, onOpenChange])

  // 在未挂载时不渲染任何内容，避免水合不匹配
  if (!mounted || !present) return null

  // 尺寸映射
  const sizeClasses = {
    sm: 'max-w-modal-sm',
    md: 'max-w-modal-md',
    lg: 'max-w-modal-lg',
    xl: 'max-w-modal-xl',
    fluid: 'w-[92vw] max-w-modal-xl'
  }

  return (
    <div
      className={cn(
        "fixed inset-0 z-modal-overlay flex motion-reduce:transition-none",
        isMobile ? "items-end justify-center" : "items-center justify-center p-4"
      )}
    >
      <div
        className={cn(
          "fixed inset-0 bg-black/50 transition-opacity duration-200 ease-out motion-reduce:transition-none",
          active ? "opacity-100" : "opacity-0 pointer-events-none"
        )}
        onClick={() => onOpenChange?.(false)}
      />
      <div
        role="dialog"
        aria-modal="true"
        className={cn(
          "relative z-modal-content w-full border bg-background shadow-lg overflow-hidden flex flex-col",
          "transition-[transform,opacity] duration-200 ease-out will-change-transform motion-reduce:transition-none",
          isMobile
            ? cn(
                "max-h-[85vh] rounded-t-xl rounded-b-none border-x-0",
                active ? "translate-y-0 opacity-100" : "translate-y-4 opacity-0 pointer-events-none"
              )
            : cn("max-h-[90vh] rounded-lg", sizeClasses[size]),
          !isMobile && (active ? "scale-100 opacity-100" : "scale-[0.98] opacity-0 pointer-events-none"),
          className
        )}
        onClick={(e) => e.stopPropagation()}
      >
        {isMobile && <div className="mx-auto mt-2 h-1.5 w-12 rounded-full bg-muted" />}
        {children}
      </div>
    </div>
  )
}

const DialogBody: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn("flex-1 overflow-y-auto px-4 sm:px-6 py-5", className)}>
    {children}
  </div>
)

const DialogFooter: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn(
    "mt-auto flex flex-col-reverse gap-2 sm:flex-row sm:justify-end px-4 sm:px-6 pt-4 pb-6 border-t",
    className
  )}>
    {children}
  </div>
)

const DialogTrigger: React.FC<{
  className?: string
  children: React.ReactNode
  asChild?: boolean
}> = ({ className, children, asChild }) => {
  const { onOpenChange } = useDialogContext()

  if (asChild && React.isValidElement(children)) {
    const child = children as React.ReactElement<any>
    return React.cloneElement(child, {
      className: cn(child.props.className, className),
      onClick: (e: any) => {
        child.props.onClick?.(e)
        if (!e?.defaultPrevented) onOpenChange?.(true)
      },
    })
  }

  return (
    <button type="button" className={cn(className)} onClick={() => onOpenChange?.(true)}>
      {children}
    </button>
  )
}

export {
  Dialog,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogContent,
  DialogBody,
  DialogFooter,
  DialogTrigger,
}
