"use client"

import { useState } from "react"
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
import { LoginDialog } from "@/components/auth/LoginDialog"
import { useAuth } from "@/contexts/AuthContext"
import { appEvents, AppEvents } from "@/lib/events"

export function UserMenu() {
  const { t } = useLanguage()
  const { token, user, logout } = useAuth()
  const [uploadDialogOpen, setUploadDialogOpen] = useState(false)
  const [loginDialogOpen, setLoginDialogOpen] = useState(false)

  const handleUploadComplete = (archiveId: string) => {
    // 上传完成后的回调
    console.log('Upload completed with archive ID:', archiveId);

    // 触发首页数据刷新事件
    appEvents.emit(AppEvents.UPLOAD_COMPLETED, archiveId);

    // 不再自动关闭抽屉，让用户可以继续上传更多文件
    // setUploadDialogOpen(false)
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
          {token ? (
            // 已登录用户菜单
            <>
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
              <DropdownMenuItem onClick={() => window.location.href = '/settings'}>
                <Settings className="mr-2 h-4 w-4" />
                <span>{t("user.settings")}</span>
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={logout}>
                <LogOut className="mr-2 h-4 w-4" />
                <span>{t("user.logout")}</span>
              </DropdownMenuItem>
            </>
          ) : (
            // 未登录用户菜单
            <DropdownMenuItem onClick={() => setLoginDialogOpen(true)}>
              <User className="mr-2 h-4 w-4" />
              <span>{t("auth.login")}</span>
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <UploadDrawer
        open={uploadDialogOpen}
        onOpenChange={setUploadDialogOpen}
        onUploadComplete={handleUploadComplete}
      />
      
      <LoginDialog
        open={loginDialogOpen}
        onOpenChange={setLoginDialogOpen}
      />
    </>
  )
}
