"use client"

import { useEffect, useState } from "react"
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
import { Dialog, DialogBody, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Upload, User, Settings, LogOut, BookOpen, X } from "lucide-react"
import { UploadDrawer } from "@/components/upload/UploadDrawer"
import { useAuth } from "@/contexts/AuthContext"
import { appEvents, AppEvents } from "@/lib/utils/events"
export function UserMenu() {
  const { t } = useLanguage()
  const router = useRouter()
  const { token, user, logout } = useAuth()
  const [uploadDialogOpen, setUploadDialogOpen] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [isMobile, setIsMobile] = useState(false)

  const handleUploadComplete = (archiveId: string) => {
    // 上传完成后的回调


    // 触发首页数据刷新事件
    // 支持上传和在线下载两种场景的刷新
    appEvents.emit(AppEvents.UPLOAD_COMPLETED, archiveId);

    // 不再自动关闭抽屉，让用户可以继续上传更多文件
    // setUploadDialogOpen(false)
  }

  useEffect(() => {
    if (typeof window === "undefined") return
    const mql = window.matchMedia("(max-width: 639px)")
    const onMediaChange = (e: MediaQueryListEvent) => setIsMobile(e.matches)
    setIsMobile(mql.matches)
    mql.addEventListener("change", onMediaChange)
    return () => mql.removeEventListener("change", onMediaChange)
  }, [])

  // Avoid leaving the drawer open when switching between breakpoints.
  useEffect(() => {
    if (!isMobile) setMobileMenuOpen(false)
  }, [isMobile])

  const openUpload = () => {
    setMobileMenuOpen(false)
    setUploadDialogOpen(true)
  }

  const goto = (href: string) => {
    setMobileMenuOpen(false)
    router.push(href)
  }

  const doLogout = () => {
    setMobileMenuOpen(false)
    logout()
  }

  const triggerButton = (
    <Button
      type="button"
      variant="ghost"
      className="relative h-10 w-10 rounded-full"
      onClick={isMobile ? () => setMobileMenuOpen(true) : undefined}
    >
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
  )

  // 如果未登录，返回空内容（菜单在 Header 中已处理）
  if (!token) {
    return null;
  }

  if (isMobile) {
    return (
      <>
        {triggerButton}

        <Dialog open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
          <DialogContent className="w-full">
            <DialogHeader className="px-4 py-3 border-b relative">
              <button
                type="button"
                className="absolute right-2 top-2 inline-flex h-9 w-9 items-center justify-center rounded-md hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                aria-label={t("common.close")}
                onClick={() => setMobileMenuOpen(false)}
              >
                <X className="h-4 w-4" />
              </button>
              <DialogTitle className="text-center">{user?.username || t("user.menu")}</DialogTitle>
              <p className="text-center text-sm text-muted-foreground">{t("user.loggedIn")}</p>
            </DialogHeader>

            <DialogBody className="px-2 py-2">
              <div className="flex flex-col">
                <Button
                  type="button"
                  variant="ghost"
                  className="w-full justify-start h-auto py-3"
                  onClick={openUpload}
                >
                  <Upload className="mr-2 h-4 w-4" />
                  <span>{t("upload.title")}</span>
                </Button>

                <Button
                  type="button"
                  variant="ghost"
                  className="w-full justify-start h-auto py-3"
                  onClick={() => goto("/library?tab=favorites")}
                >
                  <BookOpen className="mr-2 h-4 w-4" />
                  <span>{t("navigation.library")}</span>
                </Button>

                <Button
                  type="button"
                  variant="ghost"
                  className="w-full justify-start h-auto py-3"
                  onClick={() => goto("/settings")}
                >
                  <Settings className="mr-2 h-4 w-4" />
                  <span>{t("user.settings")}</span>
                </Button>

                <div className="my-2 h-px bg-border" />

                <Button
                  type="button"
                  variant="ghost"
                  className="w-full justify-start h-auto py-3 text-destructive hover:text-destructive"
                  onClick={doLogout}
                >
                  <LogOut className="mr-2 h-4 w-4" />
                  <span>{t("user.logout")}</span>
                </Button>
              </div>
            </DialogBody>
          </DialogContent>
        </Dialog>

        <UploadDrawer
          open={uploadDialogOpen}
          onOpenChange={setUploadDialogOpen}
          onUploadComplete={handleUploadComplete}
        />
      </>
    )
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
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
            <BookOpen className="mr-2 h-4 w-4" />
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
