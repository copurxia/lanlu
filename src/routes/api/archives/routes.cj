package lrr4cj.routes.api.archives

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

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
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getArchives(ctx)
        })

        // 根据 ID 获取归档
        router.get("/api/archives/{id}", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getArchive(ctx)
        })

        // 获取归档元数据
        router.get("/api/archives/{id}/metadata", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getMetadata(ctx)
        })

        // 更新归档元数据
        router.put("/api/archives/{id}/metadata", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.updateMetadata(ctx)
        })

        // 获取归档缩略图
        router.get("/api/archives/{id}/thumbnail", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getThumbnail(ctx)
        })

        // 获取归档文件列表
        router.get("/api/archives/{id}/files", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getFiles(ctx)
        })

        // 获取归档文件
        router.get("/api/archives/{id}/files/{fileIndex}", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getFile(ctx)
        })

        // 获取归档页面
        router.get("/api/archives/{id}/page", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.getPage(ctx)
        })

        // 提取归档
        router.post("/api/archives/{id}/extract", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.extractArchive(ctx)
        })

        // 删除归档
        router.delete("/api/archives/{id}", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            ArchiveController.deleteArchive(ctx)
        })
    }
}