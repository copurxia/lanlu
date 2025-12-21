"use client"

import { useState, useRef } from "react"
import { useLanguage } from "@/contexts/LanguageContext"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Progress } from "@/components/ui/progress"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ArchiveService, DownloadProgressCallback } from "@/lib/archive-service"
import { Upload, FileText, X, CheckCircle, AlertCircle, Plus, Download } from "lucide-react"

interface UploadFile {
  id: string
  file: File
  progress: number
  status: "uploading" | "success" | "error"
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
  const [internalOpen, setInternalOpen] = useState(false)
  const open = controlledOpen !== undefined ? controlledOpen : internalOpen
  const setOpen = onOpenChange || setInternalOpen
  const [uploadFiles, setUploadFiles] = useState<UploadFile[]>([])
  const [downloadTasks, setDownloadTasks] = useState<DownloadTask[]>([])
  const [urlInput, setUrlInput] = useState("")
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const supportedFormats = [".zip", ".rar", ".7z", ".tar", ".gz", ".pdf", ".epub", ".mobi", ".cbz", ".cbr"]

  const handleFileSelect = (files: FileList | null) => {
    if (!files) return

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

  const startUpload = async (uploadFile: UploadFile) => {
    try {
      const result = await ArchiveService.uploadArchiveWithChunks(uploadFile.file, {
        title: uploadFile.file.name.replace(/\.[^/.]+$/, "")
      }, {
        onProgress: (progress) => {
          setUploadFiles(prev => prev.map(f =>
            f.id === uploadFile.id ? { ...f, progress } : f
          ))
        },
        onChunkComplete: (chunkIndex, totalChunks) => {
          console.log(`文件 ${uploadFile.id} 分片 ${chunkIndex + 1}/${totalChunks} 上传完成`)
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

      await ArchiveService.downloadFromUrl(url, {}, callbacks)
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
        className="w-full sm:w-[600px] md:w-[700px] lg:w-[900px] xl:w-[1200px] overflow-y-auto"
        onInteractOutside={(e) => {
          const uploadingFiles = uploadFiles.filter(file => file.status === "uploading")
          const downloadingTasks = downloadTasks.filter(task => task.status === "downloading")
          if (uploadingFiles.length > 0 || downloadingTasks.length > 0) {
            e.preventDefault()
          }
        }}
      >
        <SheetHeader>
          <SheetTitle className="flex items-center justify-between">
            {t("upload.title")}
            <div className="flex space-x-2">
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
          </SheetTitle>
        </SheetHeader>

        <div className="mt-6">
          <Tabs defaultValue="upload" className="w-full">
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
            <TabsContent value="upload" className="space-y-6 mt-6">
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
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </TabsContent>

            {/* 在线下载标签页 */}
            <TabsContent value="download" className="space-y-6 mt-6">
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
                  disabled={!urlInput.trim()}
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

          {/* Close Button */}
          <div className="flex justify-end pt-4">
            <Button variant="outline" onClick={handleClose}>
              {t("upload.close")}
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
