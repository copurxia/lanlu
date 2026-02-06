package lanlu.routes.api.tags

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * 标签路由
 */
public func registerTagRoutes(router: JoyRouters): Unit {
    // 获取标签翻译映射
    router.get("/api/tags/translations", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.getTranslations(ctx)
    })

    // 获取所有命名空间
    router.get("/api/tags/namespaces", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.listNamespaces(ctx)
    })

    // 自动补全搜索
    router.get("/api/tags/autocomplete", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.autocomplete(ctx)
    })

    // 获取标签列表（支持分页和搜索）
    router.get("/api/tags", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.list(ctx)
    })

    // 标签词云（按使用次数）
    router.get("/api/tags/cloud", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.cloud(ctx)
    })

    // 按 name 获取标签详情
    router.get("/api/tags/by-name", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.getByName(ctx)
    })

    // 获取标签详情
    router.get("/api/tags/{id}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TagController.getById(ctx)
    })

    // 管理员接口：获取所有标签名（用于自动补全）
    router.get("/api/admin/tags/names", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminListTagNames(ctx)
            case None => return
        }
    })

    // 管理员接口：创建标签
    router.post("/api/admin/tags", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminCreate(ctx)
            case None => return
        }
    })

    // 管理员接口：更新标签
    router.put("/api/admin/tags/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminUpdate(ctx)
            case None => return
        }
    })

    // 管理员接口：上传标签图标
    router.put("/api/admin/tags/{id}/icon", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(uid) => TagController.adminUploadIcon(ctx, uid)
            case None => return
        }
    })

    // 管理员接口：上传标签背景图
    router.put("/api/admin/tags/{id}/background", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(uid) => TagController.adminUploadBackground(ctx, uid)
            case None => return
        }
    })

    // 管理员接口：删除标签
    router.delete("/api/admin/tags/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminDelete(ctx)
            case None => return
        }
    })

    // 管理员接口：导出标签
    router.get("/api/admin/tags/export", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminExport(ctx)
            case None => return
        }
    })

    // 管理员接口：分片上传导入
    router.post("/api/admin/tags/import/init", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminImportInit(ctx)
            case None => return
        }
    })

    router.put("/api/admin/tags/import/chunk", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminImportUploadChunk(ctx)
            case None => return
        }
    })

    router.post("/api/admin/tags/import/complete", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TagController.adminImportUploadComplete(ctx)
            case None => return
        }
    })
}
