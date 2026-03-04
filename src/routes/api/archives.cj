package lanlu.routes.api

import ignite.*
import lanlu.contexts.archive.interfaces.http.ArchiveController
import lanlu.contexts.archive.interfaces.http.ChunkedUploadController
import lanlu.contexts.archive.interfaces.http.DownloadController
import lanlu.contexts.archive.interfaces.http.MetadataPluginController
import lanlu.infrastructure.middleware.*

/**
 * API 归档路由模块
 * 处理 /api/archives 路径下的路由
 */
public class ArchiveRoutes {
    /**
     * 配置 API 归档相关路由
     */
    public static func configure(router: App) {
        let archives = router.group("/api/archives")
        archives.use(AuthMiddleware.requiredAuthMiddleware())

        // 获取归档元数据
        archives.get("/:id/metadata", { ctx =>
            ArchiveController.getMetadata(ctx)
        })

        // 更新归档元数据
        archives.put("/:id/metadata", { ctx =>
            ArchiveController.updateMetadata(ctx)
        })

        // 获取归档文件列表
        archives.get("/:id/files", { ctx =>
            ArchiveController.getFiles(ctx)
        })

        // 获取归档所属合集列表
        archives.get("/:id/tankoubons", { ctx =>
            ArchiveController.getTankoubonsForArchive(ctx)
        })

        // 下载归档
        archives.get("/:id/download", { ctx =>
            ArchiveController.downloadArchive(ctx)
        })

        // 获取归档页面
        archives.get("/:id/page", { ctx =>
            ArchiveController.getPage(ctx)
        })

        // 删除归档
        archives.delete("/:id", { ctx =>
            ArchiveController.deleteArchive(ctx)
        })

        // 设置归档的isNew标记
        archives.put("/:id/isnew", { ctx =>
            ArchiveController.setIsNew(ctx)
        })

        // 清除归档的isNew标记
        archives.delete("/:id/isnew", { ctx =>
            ArchiveController.clearIsNew(ctx)
        })

        // 更新阅读进度并自动标记为已读
        archives.put("/:id/progress/:page", { ctx =>
            ArchiveController.updateProgress(ctx)
        })

        // 添加收藏
        archives.put("/:id/favorite", { ctx =>
            ArchiveController.addFavorite(ctx)
        })

        // 取消收藏
        archives.delete("/:id/favorite", { ctx =>
            ArchiveController.removeFavorite(ctx)
        })

        // 分片上传 - 初始化上传会话
        archives.post("/upload/init", { ctx =>
            ChunkedUploadController.initUpload(ctx)
        })

        // 分片上传 - 上传分片
        archives.put("/upload/chunk", { ctx =>
            ChunkedUploadController.uploadChunk(ctx)
        })

        // 分片上传 - 取消上传
        archives.delete("/upload/:taskId", { ctx =>
            ChunkedUploadController.cancelUpload(ctx)
        })

        let protectedApi = router.group("/api")
        protectedApi.use(AuthMiddleware.requiredAuthMiddleware())

        // 从URL下载档案
        protectedApi.post("/download_url", { ctx =>
            DownloadController.downloadFromUrl(ctx)
        })

        // 执行元数据插件（进入TaskPool，返回job id）
        protectedApi.post("/metadata_plugin", { ctx =>
            MetadataPluginController.runMetadataPlugin(ctx)
        })
    }
}
