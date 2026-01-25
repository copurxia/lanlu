package lanlu.routes.api.database

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * API 数据库路由模块
 * 处理 /api/database 路径下的路由
 */
public class DatabaseRoutes {
    /**
     * 配置 API 数据库相关路由
     */
    public static func configure(router: JoyRouters) {
        // 获取数据库统计信息
        router.get("/api/database/stats", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.getDatabaseStats(ctx)
        })

        // 数据库健康检查
        router.get("/api/database/health", { ctx => DatabaseController.healthCheck(ctx) })

        // 获取数据库配置信息
        router.get("/api/database/config", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.getDatabaseConfig(ctx)
        })

        // 获取数据库备份
        router.get("/api/database/backup", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.getDatabaseBackup(ctx)
        })

        // 清理数据库
        router.post("/api/database/clean", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.cleanDatabase(ctx)
        })

        // 恢复数据库备份
        router.post("/api/database/restore", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.restoreDatabaseBackup(ctx)
        })

        // 重建搜索索引
        router.post("/api/database/reindex", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.rebuildSearchIndex(ctx)
        })

        // 删除数据库
        router.post("/api/database/drop", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            DatabaseController.dropDatabase(ctx)
        })
    }
}
