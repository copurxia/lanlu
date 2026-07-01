package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.archive.interfaces.http.ArchiveController
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
    public static func configure(router: Router) {
        router.group("/api/archives") { archives =>
            archives.use(AuthMiddleware.requiredAuthMiddleware())

            // 获取归档元数据
            archives.get("/:id/metadata", { ctx: Context, next: Next =>
                ArchiveController.getMetadata(ctx)
            })

            // 更新归档元数据
            archives.put("/:id/metadata", audited("archive.metadata.update", { ctx: Context, next: Next =>
                ArchiveController.updateMetadata(ctx)
            }, riskLevel: 3))

            // 获取归档文件列表
            archives.get("/:id/files", { ctx: Context, next: Next =>
                ArchiveController.getFiles(ctx)
            })

            // 获取归档所属合集列表
            archives.get("/:id/tankoubons", { ctx: Context, next: Next =>
                ArchiveController.getTankoubonsForArchive(ctx)
            })

            // 下载归档
            archives.get("/:id/download/parts", { ctx: Context, next: Next =>
                ArchiveController.getArchiveDownloadParts(ctx)
            })
            archives.get("/:id/download", { ctx: Context, next: Next =>
                ArchiveController.downloadArchive(ctx)
            })

            // 获取归档页面
            archives.get("/:id/page", { ctx: Context, next: Next =>
                ArchiveController.getPage(ctx)
            })
            archives.head("/:id/page", { ctx: Context, next: Next =>
                ArchiveController.getPage(ctx)
            })

            // 获取/创建归档封面
            archives.get("/:id/cover", { ctx: Context, next: Next =>
                ArchiveController.getCover(ctx)
            })

            // 删除归档
            archives.delete("/:id", audited("archive.delete", { ctx: Context, next: Next =>
                ArchiveController.deleteArchive(ctx)
            }, riskLevel: 2))

            // 设置归档的isNew标记
            archives.put("/:id/isnew", audited("archive.isnew.set", { ctx: Context, next: Next =>
                ArchiveController.setIsNew(ctx)
            }, riskLevel: 4))

            // 清除归档的isNew标记
            archives.delete("/:id/isnew", audited("archive.isnew.clear", { ctx: Context, next: Next =>
                ArchiveController.clearIsNew(ctx)
            }, riskLevel: 4))

            // 更新阅读进度并自动标记为已读
            archives.put("/:id/progress/:page", audited("archive.progress.update", { ctx: Context, next: Next =>
                ArchiveController.updateProgress(ctx)
            }, riskLevel: 4))

            // 添加收藏
            archives.put("/:id/favorite", audited("archive.favorite.add", { ctx: Context, next: Next =>
                ArchiveController.addFavorite(ctx)
            }, riskLevel: 4))

            // 取消收藏
            archives.delete("/:id/favorite", audited("archive.favorite.remove", { ctx: Context, next: Next =>
                ArchiveController.removeFavorite(ctx)
            }, riskLevel: 4))
        }

        router.group("/api") { protectedApi =>
            protectedApi.use(AuthMiddleware.requiredAuthMiddleware())

            // 从URL下载档案
            protectedApi.post("/download_url", audited("archive.download_url.create", { ctx: Context, next: Next =>
                DownloadController.downloadFromUrl(ctx)
            }, riskLevel: 2))

            // 执行元数据插件（进入TaskPool，返回job id）
            protectedApi.post("/metadata_plugin", audited("archive.metadata_plugin.run", { ctx: Context, next: Next =>
                MetadataPluginController.runMetadataPlugin(ctx)
            }, riskLevel: 2))
        }
    }
}