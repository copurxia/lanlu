/**
 * UserMenu组件 - 使用UnifiedMenu实现
 * @module UserMenu
 */

"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { useLanguage } from "@/contexts/LanguageContext"
import { Button } from "@/components/ui/button"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Upload, User, Settings, LogOut, BookOpen } from "lucide-react"
import { UploadDrawer } from "@/components/upload/UploadDrawer"
import { useAuth } from "@/contexts/AuthContext"
import { appEvents, AppEvents } from "@/lib/utils/events"
import { UnifiedMenu, type MenuItem } from "@/components/ui/unified-menu"

export function UserMenu() {
  const { t } = useLanguage()
  const router = useRouter()
  const { token, user, logout } = useAuth()
  const [uploadDialogOpen, setUploadDialogOpen] = useState(false)

  const handleUploadComplete = (archiveId: string) => {
    // 触发首页数据刷新事件
    appEvents.emit(AppEvents.UPLOAD_COMPLETED, archiveId)
  }

  const openUpload = () => {
    setUploadDialogOpen(true)
  }

  const goto = (href: string) => {
    router.push(href)
  }

  // 如果未登录，返回空内容（菜单在 Header 中已处理）
  if (!token) {
    return null
  }

  // 构建菜单项配置
  const userMenuItems: MenuItem[] = [
    {
      id: "upload",
      label: t("upload.title"),
      icon: Upload,
      onClick: openUpload,
    },
    {
      id: "library",
      label: t("navigation.library"),
      icon: BookOpen,
      onClick: () => goto("/library?tab=favorites"),
    },
    {
      id: "settings",
      label: t("user.settings"),
      icon: Settings,
      onClick: () => goto("/settings"),
    },
    {
      id: "logout",
      label: t("user.logout"),
      icon: LogOut,
      danger: true,
      onClick: logout,
    },
  ]

  // 处理菜单选择
  const handleSelect = (id: string) => {
    switch (id) {
      case "upload":
        openUpload()
        break
      case "library":
        goto("/library?tab=favorites")
        break
      case "settings":
        goto("/settings")
        break
      case "logout":
        logout()
        break
    }
  }

  return (
    <>
      <UnifiedMenu
        items={userMenuItems}
        trigger="click"
        align="end"
        title={user?.username || t("user.menu")}
        onSelect={handleSelect}
        triggerElement={
          <Button variant="ghost" className="relative h-10 w-10 rounded-full">
            <Avatar className="h-10 w-10">
              <AvatarImage
                src={user?.avatarAssetId ? `/api/assets/${user.avatarAssetId}` : ""}
                alt={t("user.menu")}
              />
              <AvatarFallback>
                <User className="h-5 w-5" />
              </AvatarFallback>
            </Avatar>
          </Button>
        }
      />

      <UploadDrawer
        open={uploadDialogOpen}
        onOpenChange={setUploadDialogOpen}
        onUploadComplete={handleUploadComplete}
      />
    </>
  )
}
