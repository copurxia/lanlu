package lanlu.routes.api.archives

import cjoy.*
import lanlu.controllers.*
import lanlu.controllers.ChunkedUploadController
import lanlu.controllers.DownloadController
import lanlu.middleware.*

/**
 * API 归档路由模块
 * 处理 /api/archives 路径下的路由
 */
public class ArchiveRoutes {
    /**
     * 配置 API 归档相关路由
     */
    public static func configure(router: JoyRouters) {
        // 获取所有归档
        router.get("/api/archives", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.getArchives(ctx)
        })

        // 根据 ID 获取归档
        router.get("/api/archives/{id}", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.getArchive(ctx)
        })

        // 获取归档元数据
        router.get("/api/archives/{id}/metadata", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.getMetadata(ctx)
        })

        // 更新归档元数据
        router.put("/api/archives/{id}/metadata", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.updateMetadata(ctx)
        })

        // 获取归档缩略图（无需认证）
        router.get("/api/archives/{id}/thumbnail", { ctx =>
            ArchiveController.getThumbnail(ctx)
        })

        // 获取归档文件列表
        router.get("/api/archives/{id}/files", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.getFiles(ctx)
        })

        // 获取归档所属合集列表
        router.get("/api/archives/{id}/tankoubons", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.getTankoubonsForArchive(ctx)
        })

        // 下载归档
        router.get("/api/archives/{id}/download", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.downloadArchive(ctx)
        })

        // 获取归档页面
        router.get("/api/archives/{id}/page", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.getPage(ctx)
        })

        // 删除归档
        router.delete("/api/archives/{id}", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.deleteArchive(ctx)
        })

        // 设置归档的isNew标记
        router.put("/api/archives/{id}/isnew", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.setIsNew(ctx)
        })

        // 清除归档的isNew标记
        router.delete("/api/archives/{id}/isnew", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.clearIsNew(ctx)
        })

        // 更新阅读进度并自动标记为已读
        router.put("/api/archives/{id}/progress/{page}", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.updateProgress(ctx)
        })

        // 添加收藏
        router.put("/api/archives/{id}/favorite", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.addFavorite(ctx)
        })

        // 取消收藏
        router.delete("/api/archives/{id}/favorite", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ArchiveController.removeFavorite(ctx)
        })

        // 分片上传 - 初始化上传会话
        router.post("/api/archives/upload/init", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ChunkedUploadController.initUpload(ctx)
        })

        // 分片上传 - 上传分片
        router.put("/api/archives/upload/chunk", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ChunkedUploadController.uploadChunk(ctx)
        })

        

        // 分片上传 - 完成上传
        router.get("/api/archives/upload/complete", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            ChunkedUploadController.completeUpload(ctx)
        })

        // 从URL下载档案
        router.post("/api/download_url", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DownloadController.downloadFromUrl(ctx)
        })
        router.get("/api/download_url", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DownloadController.downloadFromUrl(ctx)
        })

        // 执行元数据插件（进入TaskPool，返回job id）
        router.post("/api/metadata_plugin", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            MetadataPluginController.runMetadataPlugin(ctx)
        })
    }
}
