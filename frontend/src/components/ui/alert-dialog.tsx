"use client"

import * as React from "react"
import { cn } from "@/lib/utils"

interface AlertDialogProps {
  open?: boolean
  onOpenChange?: (open: boolean) => void
  children: React.ReactNode
}

const AlertDialog: React.FC<AlertDialogProps> = ({ open, onOpenChange, children }) => {
  return (
    <>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div
            className="fixed inset-0 bg-black/50"
            onClick={() => onOpenChange?.(false)}
          />
          <div className="relative z-50 w-full max-w-lg rounded-lg border bg-background shadow-lg">
            {children}
          </div>
        </div>
      )}
    </>
  )
}

const AlertDialogHeader: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn("flex flex-col space-y-2 text-center sm:text-left px-6 pt-6", className)}>
    {children}
  </div>
)

const AlertDialogTitle: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <h2 className={cn("text-lg font-semibold", className)}>
    {children}
  </h2>
)

const AlertDialogDescription: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <p className={cn("text-sm text-muted-foreground", className)}>
    {children}
  </p>
)

const AlertDialogContent: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn("px-6 py-4", className)}>
    {children}
  </div>
)

const AlertDialogFooter: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn("flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2 px-6 pb-6", className)}>
    {children}
  </div>
)

const AlertDialogAction: React.FC<{
  className?: string
  children: React.ReactNode
  onClick?: () => void
  disabled?: boolean
}> = ({ className, children, onClick, disabled }) => (
  <button
    type="button"
    onClick={onClick}
    disabled={disabled}
    className={cn(
      "inline-flex h-10 items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground ring-offset-background transition-colors hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
      className
    )}
  >
    {children}
  </button>
)

const AlertDialogCancel: React.FC<{
  className?: string
  children: React.ReactNode
  onClick?: () => void
}> = ({ className, children, onClick }) => (
  <button
    type="button"
    onClick={onClick}
    className={cn(
      "mt-2 sm:mt-0 inline-flex h-10 items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-semibold ring-offset-background transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
      className
    )}
  >
    {children}
  </button>
)

export {
  AlertDialog,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogContent,
  AlertDialogFooter,
  AlertDialogAction,
  AlertDialogCancel,
}
