"use client"

import { useLanguage } from "@/contexts/LanguageContext"
import { Button } from "@/components/ui/button"
import { UploadDrawer } from "./UploadDrawer"
import { Upload } from "lucide-react"

interface UploadButtonProps {
  onUploadComplete?: (archiveId: string) => void
}

export function UploadButton({ onUploadComplete }: UploadButtonProps) {
  const { t } = useLanguage()

  return (
    <UploadDrawer 
      onUploadComplete={onUploadComplete}
      trigger={
        <Button>
          <Upload className="mr-2 h-4 w-4" />
          {t("upload.title")}
        </Button>
      }
    />
  )
}