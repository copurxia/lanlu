"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { useLanguage } from "@/contexts/LanguageContext"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Upload, User, Settings, LogOut } from "lucide-react"
import { UploadDrawer } from "@/components/upload/UploadDrawer"
import { useAuth } from "@/contexts/AuthContext"
import { appEvents, AppEvents } from "@/lib/utils/events"
import { Heart } from "lucide-react"

export function UserMenu() {
  const { t } = useLanguage()
  const router = useRouter()
  const { token, user, logout } = useAuth()
  const [uploadDialogOpen, setUploadDialogOpen] = useState(false)

  const handleUploadComplete = (archiveId: string) => {
    // 上传完成后的回调


    // 触发首页数据刷新事件
    // 支持上传和在线下载两种场景的刷新
    appEvents.emit(AppEvents.UPLOAD_COMPLETED, archiveId);

    // 不再自动关闭抽屉，让用户可以继续上传更多文件
    // setUploadDialogOpen(false)
  }

  // 如果未登录，返回空内容（菜单在 Header 中已处理）
  if (!token) {
    return null;
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" className="relative h-10 w-10 rounded-full">
            <Avatar className="h-10 w-10">
              <AvatarImage src="" alt={t("user.menu")} />
              <AvatarFallback>
                <User className="h-5 w-5" />
              </AvatarFallback>
            </Avatar>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent className="w-56" align="end">
          {/* 已登录用户菜单 */}
          <div className="flex items-center justify-start gap-2 p-2">
            <div className="flex flex-col space-y-1 leading-none">
              <p className="font-medium">{user?.username || t("user.menu")}</p>
              <p className="w-[200px] truncate text-sm text-muted-foreground">
                {t("user.loggedIn")}
              </p>
            </div>
          </div>
          <DropdownMenuItem onClick={() => setUploadDialogOpen(true)}>
            <Upload className="mr-2 h-4 w-4" />
            <span>{t("upload.title")}</span>
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => router.push('/library?tab=favorites')}>
            <Heart className="mr-2 h-4 w-4" />
            <span>{t("navigation.library")}</span>
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => router.push('/settings')}>
            <Settings className="mr-2 h-4 w-4" />
            <span>{t("user.settings")}</span>
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={logout}>
            <LogOut className="mr-2 h-4 w-4" />
            <span>{t("user.logout")}</span>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <UploadDrawer
        open={uploadDialogOpen}
        onOpenChange={setUploadDialogOpen}
        onUploadComplete={handleUploadComplete}
      />
    </>
  )
}
