"use client"

import * as React from "react"
import { cn } from "@/lib/utils"
import { Dialog, DialogContent } from "./dialog"

interface AlertDialogProps {
  open?: boolean
  onOpenChange?: (open: boolean) => void
  children: React.ReactNode
}

const AlertDialog: React.FC<AlertDialogProps> = ({ open, onOpenChange, children }) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      {children}
    </Dialog>
  )
}

const AlertDialogHeader: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn("flex flex-col gap-1.5 text-center sm:text-left px-6 pt-6 pb-4", className)}>
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

interface AlertDialogContentProps {
  className?: string
  children: React.ReactNode
  size?: 'sm' | 'md' | 'lg' | 'xl' | 'fluid'
}

const AlertDialogContent: React.FC<AlertDialogContentProps> = ({
  className,
  children,
  size = 'md'
}) => {
  return (
    <DialogContent size={size} className={className}>
      {children}
    </DialogContent>
  )
}

const AlertDialogFooter: React.FC<{ className?: string; children: React.ReactNode }> = ({
  className,
  children
}) => (
  <div className={cn(
    "mt-auto flex flex-col-reverse gap-2 sm:flex-row sm:justify-end px-6 pt-4 pb-6 border-t",
    className
  )}>
    {children}
  </div>
)

const AlertDialogAction: React.FC<{
  className?: string
  children: React.ReactNode
  onClick?: () => void
  disabled?: boolean
  variant?: 'default' | 'destructive'
}> = ({ className, children, onClick, disabled, variant = 'default' }) => (
  <button
    type="button"
    onClick={onClick}
    disabled={disabled}
    className={cn(
      "inline-flex h-10 items-center justify-center rounded-md px-4 py-2 text-sm font-semibold ring-offset-background transition-colors",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
      "disabled:pointer-events-none disabled:opacity-50",
      variant === 'destructive'
        ? "bg-destructive text-destructive-foreground hover:bg-destructive/90"
        : "bg-primary text-primary-foreground hover:bg-primary/90",
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
