"use client"

import { useState, useRef, useEffect } from "react"
import { useLanguage } from "@/contexts/LanguageContext"
import { useToast } from "@/hooks/use-toast"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Progress } from "@/components/ui/progress"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ArchiveService, DownloadProgressCallback } from "@/lib/archive-service"
import { CategoryService, type Category } from "@/lib/category-service"
import { Upload, FileText, X, CheckCircle, AlertCircle, Plus, Download, FolderOpen, RefreshCw } from "lucide-react"

interface UploadFile {
  id: string
  file: File
  progress: number
  status: "uploading" | "success" | "error" | "fileExists"
  error?: string
}

interface DownloadTask {
  id: string
  url: string
  progress: number
  status: "downloading" | "success" | "error"
  error?: string
}

interface UploadDrawerProps {
  open?: boolean
  onOpenChange?: (open: boolean) => void
  onUploadComplete?: (archiveId: string) => void
  trigger?: React.ReactNode
}

export function UploadDrawer({ open: controlledOpen, onOpenChange, onUploadComplete, trigger }: UploadDrawerProps) {
  const { t } = useLanguage()
  const { error: showError } = useToast()
  const [internalOpen, setInternalOpen] = useState(false)
  const open = controlledOpen !== undefined ? controlledOpen : internalOpen
  const setOpen = onOpenChange || setInternalOpen
  const [uploadFiles, setUploadFiles] = useState<UploadFile[]>([])
  const [downloadTasks, setDownloadTasks] = useState<DownloadTask[]>([])
  const [urlInput, setUrlInput] = useState("")
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [categories, setCategories] = useState<Category[]>([])
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>("")
  const [loadingCategories, setLoadingCategories] = useState(false)
  const selectedCategoryInternalId = categories.find(cat => cat.catid === selectedCategoryId)?.id

  const supportedFormats = [".zip", ".rar", ".7z", ".tar", ".gz", ".pdf", ".epub", ".mobi", ".cbz", ".cbr"]

  // 加载分类列表
  useEffect(() => {
    const loadCategories = async () => {
      try {
        setLoadingCategories(true)
        const cats = await CategoryService.getAllCategories()
        const enabledCats = cats.filter(cat => cat.enabled)
        setCategories(enabledCats)
        // 如果有可用的分类且当前未选择，自动选择第一个
        if (enabledCats.length > 0) {
          setSelectedCategoryId((prev) => prev || enabledCats[0].catid)
        }
      } catch (error) {
        console.error("Failed to load categories:", error)
      } finally {
        setLoadingCategories(false)
      }
    }

    if (open) {
      loadCategories()
    }
  }, [open])

  const handleFileSelect = (files: FileList | null) => {
    if (!files) return

    // 检查是否已选择分类
    if (!selectedCategoryId) {
      showError("请先选择要上传到的分类")
      return
    }
    if (!selectedCategoryInternalId) {
      showError("分类信息无效，请刷新后重试")
      return
    }

    Array.from(files).forEach(file => {
      const fileExtension = "." + file.name.split(".").pop()?.toLowerCase()
      if (supportedFormats.includes(fileExtension)) {
        const uploadFile: UploadFile = {
          id: Math.random().toString(36).substr(2, 9),
          file,
          progress: 0,
          status: "uploading"
        }
        setUploadFiles(prev => [...prev, uploadFile])
        // 立即开始上传
        startUpload(uploadFile)
      }
    })
  }

  const startUpload = async (uploadFile: UploadFile, overwrite: boolean = false) => {
    try {
      const result = await ArchiveService.uploadArchiveWithChunks(uploadFile.file, {
        title: uploadFile.file.name.replace(/\.[^/.]+$/, ""),
        categoryId: selectedCategoryInternalId,
        overwrite
      }, {
        onProgress: (progress) => {
          setUploadFiles(prev => prev.map(f =>
            f.id === uploadFile.id ? { ...f, progress } : f
          ))
        },
        onChunkComplete: () => {
          // Chunk upload progress callback
        },
        onError: (error, chunkIndex) => {
          console.error(`文件 ${uploadFile.id} 分片上传错误:`, error, chunkIndex)
        }
      })

      setUploadFiles(prev => prev.map(f => {
        if (f.id === uploadFile.id) {
          if (result.success && result.taskId) {
            setTimeout(() => {
              onUploadComplete?.(result.taskId!)
            }, 1500)
            return { ...f, progress: 100, status: "success" }
          } else if (result.fileExists) {
            // 文件已存在，显示强制上传按钮
            return { ...f, status: "fileExists", error: result.error || "文件已存在" }
          } else {
            return { ...f, status: "error", error: result.error || t("upload.uploadFailed") }
          }
        }
        return f
      }))
    } catch {
      setUploadFiles(prev => prev.map(f =>
        f.id === uploadFile.id ? { ...f, status: "error", error: t("upload.uploadFailed") } : f
      ))
    }
  }

  // 强制上传（覆盖已存在的文件）
  const forceUpload = (uploadFile: UploadFile) => {
    // 重置状态为上传中
    setUploadFiles(prev => prev.map(f =>
      f.id === uploadFile.id ? { ...f, status: "uploading", progress: 0, error: undefined } : f
    ))
    // 以 overwrite=true 重新上传
    startUpload(uploadFile, true)
  }

  const handleFileInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    handleFileSelect(event.target.files)
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
  }

  const handleDragOver = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault()
    event.stopPropagation()
    setIsDragging(true)
  }

  const handleDragLeave = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault()
    event.stopPropagation()
    setIsDragging(false)
  }

  const handleDrop = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault()
    event.stopPropagation()
    setIsDragging(false)
    
    handleFileSelect(event.dataTransfer.files)
  }

  const removeFile = (id: string) => {
    setUploadFiles(prev => prev.filter(file => file.id !== id))
  }

  const removeDownloadTask = (id: string) => {
    setDownloadTasks(prev => prev.filter(task => task.id !== id))
  }

  const startDownload = async (url: string) => {
    // 检查是否已选择分类
    if (!selectedCategoryId) {
      showError("请先选择要下载到的分类")
      return
    }
    if (!selectedCategoryInternalId) {
      showError("分类信息无效，请刷新后重试")
      return
    }

    const task: DownloadTask = {
      id: Math.random().toString(36).substr(2, 9),
      url,
      progress: 0,
      status: "downloading"
    }
    setDownloadTasks(prev => [...prev, task])

    try {
      const callbacks: DownloadProgressCallback = {
        onProgress: (progress) => {
          setDownloadTasks(prev => prev.map(t =>
            t.id === task.id ? { ...t, progress } : t
          ))
        },
        onComplete: (result) => {
          if (result.success) {
            setDownloadTasks(prev => prev.map(t =>
              t.id === task.id ? { ...t, status: "success", progress: 100 } : t
            ))
            // 下载成功，无论是否有 id 都触发刷新
            // 如果有 id，传递具体 ID；否则传递空字符串表示需要刷新所有
            setTimeout(() => {
              onUploadComplete?.(result.id || "")
            }, 1500)
          } else {
            setDownloadTasks(prev => prev.map(t =>
              t.id === task.id ? { ...t, status: "error", error: result.error || "下载失败" } : t
            ))
          }
        },
        onError: (error) => {
          setDownloadTasks(prev => prev.map(t =>
            t.id === task.id ? { ...t, status: "error", error } : t
          ))
        }
      }

      await ArchiveService.downloadFromUrl(url, { categoryId: selectedCategoryInternalId }, callbacks)
    } catch {
      setDownloadTasks(prev => prev.map(t =>
        t.id === task.id ? { ...t, status: "error", error: "下载失败" } : t
      ))
    }
  }

  const handleAddDownloadUrls = () => {
    const urlLines = urlInput.split('\n').filter(url => url.trim()).map(url => url.trim())
    urlLines.forEach(url => {
      startDownload(url)
    })
    setUrlInput("")
  }

  const clearAll = () => {
    setUploadFiles([])
    setDownloadTasks([])
    setSelectedCategoryId("")
  }

  const handleClose = () => {
    const uploadingFiles = uploadFiles.filter(file => file.status === "uploading")
    const downloadingTasks = downloadTasks.filter(task => task.status === "downloading")

    if (uploadingFiles.length === 0 && downloadingTasks.length === 0) {
      setOpen(false)
      clearAll()
      setDownloadTasks([])
    }
  }

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      {trigger && <SheetTrigger asChild>{trigger}</SheetTrigger>}
      <SheetContent
        side="right"
        className="w-full sm:w-[600px] md:w-[700px] lg:w-[900px] xl:w-[1200px] overflow-y-auto flex flex-col"
        onInteractOutside={(e) => {
          const uploadingFiles = uploadFiles.filter(file => file.status === "uploading")
          const downloadingTasks = downloadTasks.filter(task => task.status === "downloading")
          if (uploadingFiles.length > 0 || downloadingTasks.length > 0) {
            e.preventDefault()
          }
        }}
      >
        <SheetHeader>
          <SheetTitle>{t("upload.title")}</SheetTitle>
        </SheetHeader>

        <div className="flex-1 mt-6 min-h-0">
          <Tabs defaultValue="upload" className="w-full h-full flex flex-col">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="upload" className="flex items-center space-x-2">
                <Upload className="h-4 w-4" />
                <span>{t("upload.tabs.upload") || "上传档案"}</span>
              </TabsTrigger>
              <TabsTrigger value="download" className="flex items-center space-x-2">
                <Download className="h-4 w-4" />
                <span>{t("upload.tabs.download") || "在线下载"}</span>
              </TabsTrigger>
            </TabsList>

            {/* 上传档案标签页 */}
            <TabsContent value="upload" className="flex-1 overflow-y-auto mt-6 space-y-6">
              {/* 分类选择 */}
              <div className="space-y-2">
                <Label htmlFor="category-select">选择分类 *</Label>
                <Select value={selectedCategoryId} onValueChange={setSelectedCategoryId}>
                  <SelectTrigger id="category-select">
                    <SelectValue placeholder="请选择要上传到的分类" />
                  </SelectTrigger>
                  <SelectContent>
                    {loadingCategories ? (
                      <SelectItem value="loading" disabled>加载中...</SelectItem>
                    ) : categories.length === 0 ? (
                      <SelectItem value="no-categories" disabled>暂无可用分类</SelectItem>
                    ) : (
                      categories.map((category) => (
                        <SelectItem key={category.catid} value={category.catid}>
                          <div className="flex items-center gap-2">
                            <FolderOpen className="h-4 w-4" />
                            <span>{category.name}</span>
                          </div>
                        </SelectItem>
                      ))
                    )}
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">
                  {t("upload.categoryHint") || "请选择要上传档案的目标分类"}
                </p>
              </div>

              {/* File Upload Area */}
              <div
                className={`border-2 border-dashed rounded-lg p-6 text-center transition-colors ${
                  isDragging ? "border-primary bg-primary/5" : "border-gray-300 hover:border-gray-400"
                }`}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
              >
                <div className="space-y-2">
                  <Upload className="mx-auto h-12 w-12 text-gray-400" />
                  <p className="text-lg font-medium">{t("upload.dragOrClick")}</p>
                  <p className="text-sm text-gray-500">
                    {t("upload.supportedFormats")}: {supportedFormats.join(", ")}
                  </p>
                  <Button
                    variant="outline"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    <Plus className="mr-2 h-4 w-4" />
                    {t("upload.browse")}
                  </Button>
                </div>
                <input
                  ref={fileInputRef}
                  type="file"
                  className="hidden"
                  onChange={handleFileInputChange}
                  accept={supportedFormats.join(",")}
                  multiple
                />
              </div>

              {/* Upload List */}
              {uploadFiles.length > 0 && (
                <div className="space-y-4">
                  <h3 className="text-lg font-medium">{t("upload.fileList")}</h3>

                  <div className="max-h-[60vh] overflow-y-auto pr-2 space-y-4">
                    {uploadFiles.map((uploadFile) => (
                      <div key={uploadFile.id} className="border rounded-lg p-4 space-y-3">
                        {/* File Header */}
                        <div className="flex items-center justify-between">
                          <div className="flex items-center space-x-2 flex-1 min-w-0">
                            <FileText className="h-5 w-5 text-primary flex-shrink-0" />
                            <span className="font-medium truncate">{uploadFile.file.name}</span>
                            <span className="text-sm text-gray-500 flex-shrink-0">
                              ({(uploadFile.file.size / 1024 / 1024).toFixed(2)} MB)
                            </span>
                          </div>
                          <div className="flex items-center space-x-2">
                            {uploadFile.status === "success" && (
                              <CheckCircle className="h-5 w-5 text-green-600" />
                            )}
                            {uploadFile.status === "error" && (
                              <AlertCircle className="h-5 w-5 text-red-600" />
                            )}
                            {uploadFile.status === "fileExists" && (
                              <AlertCircle className="h-5 w-5 text-amber-500" />
                            )}
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => removeFile(uploadFile.id)}
                              disabled={uploadFile.status === "uploading"}
                              className="h-8 w-8 p-0"
                            >
                              <X className="h-4 w-4" />
                            </Button>
                          </div>
                        </div>

                        {/* Progress Bar */}
                        {uploadFile.status === "uploading" && (
                          <div className="space-y-2">
                            <div className="flex justify-between text-sm">
                              <span>{t("upload.uploading")}</span>
                              <span>{uploadFile.progress}%</span>
                            </div>
                            <Progress value={uploadFile.progress} className="w-full" />
                          </div>
                        )}

                        {/* Error Message */}
                        {uploadFile.status === "error" && uploadFile.error && (
                          <div className="text-sm text-red-600">{uploadFile.error}</div>
                        )}

                        {/* File Exists - 显示强制上传按钮 */}
                        {uploadFile.status === "fileExists" && (
                          <div className="flex items-center justify-between">
                            <div className="text-sm text-amber-600">{uploadFile.error}</div>
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => forceUpload(uploadFile)}
                              className="ml-2"
                            >
                              <RefreshCw className="mr-1 h-3 w-3" />
                              强制覆盖
                            </Button>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </TabsContent>

            {/* 在线下载标签页 */}
            <TabsContent value="download" className="flex-1 overflow-y-auto mt-6 space-y-6">
              {/* 分类选择 */}
              <div className="space-y-2">
                <Label htmlFor="download-category-select">选择分类 *</Label>
                <Select value={selectedCategoryId} onValueChange={setSelectedCategoryId}>
                  <SelectTrigger id="download-category-select">
                    <SelectValue placeholder="请选择要下载到的分类" />
                  </SelectTrigger>
                  <SelectContent>
                    {loadingCategories ? (
                      <SelectItem value="loading" disabled>加载中...</SelectItem>
                    ) : categories.length === 0 ? (
                      <SelectItem value="no-categories" disabled>暂无可用分类</SelectItem>
                    ) : (
                      categories.map((category) => (
                        <SelectItem key={category.catid} value={category.catid}>
                          <div className="flex items-center gap-2">
                            <FolderOpen className="h-4 w-4" />
                            <span>{category.name}</span>
                          </div>
                        </SelectItem>
                      ))
                    )}
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">
                  {t("download.categoryHint") || "请选择要下载档案的目标分类"}
                </p>
              </div>

              <div className="space-y-4">
                <div>
                  <Label htmlFor="url-input">{t("download.urlInput") || "下载链接（每行一个）"}</Label>
                  <Textarea
                    id="url-input"
                    value={urlInput}
                    onChange={(e) => setUrlInput(e.target.value)}
                    placeholder={t("download.urlPlaceholder") || "请输入下载链接，每行一个URL..."}
                    rows={6}
                    className="mt-2"
                  />
                </div>
                <Button
                  onClick={() => {
                    handleAddDownloadUrls()
                  }}
                  disabled={!urlInput.trim() || !selectedCategoryId}
                  className="w-full"
                >
                  <Plus className="mr-2 h-4 w-4" />
                  {t("download.addUrls") || "添加下载任务"}
                </Button>
              </div>

              {/* Download List */}
              {downloadTasks.length > 0 && (
                <div className="space-y-4">
                  <h3 className="text-lg font-medium">{t("download.taskList") || "下载任务列表"}</h3>

                  <div className="max-h-[60vh] overflow-y-auto pr-2 space-y-4">
                    {downloadTasks.map((task) => (
                      <div key={task.id} className="border rounded-lg p-4 space-y-3">
                        {/* Task Header */}
                        <div className="flex items-center justify-between">
                          <div className="flex items-center space-x-2 flex-1 min-w-0">
                            <Download className="h-5 w-5 text-primary flex-shrink-0" />
                            <span className="font-medium truncate">{task.url}</span>
                          </div>
                          <div className="flex items-center space-x-2">
                            {task.status === "success" && (
                              <CheckCircle className="h-5 w-5 text-green-600" />
                            )}
                            {task.status === "error" && (
                              <AlertCircle className="h-5 w-5 text-red-600" />
                            )}
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => removeDownloadTask(task.id)}
                              disabled={task.status === "downloading"}
                              className="h-8 w-8 p-0"
                            >
                              <X className="h-4 w-4" />
                            </Button>
                          </div>
                        </div>

                        {/* Progress Bar */}
                        {task.status === "downloading" && (
                          <div className="space-y-2">
                            <div className="flex justify-between text-sm">
                              <span>{t("download.downloading") || "下载中"}</span>
                              <span>{task.progress}%</span>
                            </div>
                            <Progress value={task.progress} className="w-full" />
                          </div>
                        )}

                        {/* Error Message */}
                        {task.status === "error" && task.error && (
                          <div className="text-sm text-red-600">{task.error}</div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </TabsContent>
          </Tabs>
        </div>

        {/* Bottom Action Bar */}
        <div className="border-t pt-4 mt-4 space-y-3">
          <div className="flex items-center justify-between gap-2">
            <div className="flex gap-2">
              {(uploadFiles.some(file => file.status === "success") || downloadTasks.some(task => task.status === "success")) && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setUploadFiles(prev => prev.filter(file => file.status !== "success"))
                    setDownloadTasks(prev => prev.filter(task => task.status !== "success"))
                  }}
                >
                  {t("upload.clearCompleted")}
                </Button>
              )}
              {(uploadFiles.length > 0 || downloadTasks.length > 0) && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    clearAll()
                    setDownloadTasks([])
                  }}
                >
                  {t("upload.clearAll")}
                </Button>
              )}
            </div>
            <Button onClick={handleClose}>
              {t("upload.close")}
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
