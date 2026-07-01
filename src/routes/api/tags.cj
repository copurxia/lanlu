package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.tag.interfaces.http.TagController
import lanlu.infrastructure.middleware.*

/**
 * 标签路由
 */
public func registerTagRoutes(router: Router): Unit {
    router.group("/api/tags") { tags =>
        tags.use(AuthMiddleware.requiredAuthMiddleware())

        // 获取标签翻译映射
        tags.get("/translations", { ctx: Context, next: Next =>
            TagController.getTranslations(ctx)
        })

        // 获取所有命名空间
        tags.get("/namespaces", { ctx: Context, next: Next =>
            TagController.listNamespaces(ctx)
        })

        // 自动补全搜索
        tags.get("/autocomplete", { ctx: Context, next: Next =>
            TagController.autocomplete(ctx)
        })

        // 获取标签列表（支持分页和搜索）
        tags.get("", { ctx: Context, next: Next =>
            TagController.list(ctx)
        })

        // 标签词云（按使用次数）
        tags.get("/cloud", { ctx: Context, next: Next =>
            TagController.cloud(ctx)
        })

        // 按 name 获取标签详情
        tags.get("/by-name", { ctx: Context, next: Next =>
            TagController.getByName(ctx)
        })

        // 获取标签详情
        tags.get("/:id", { ctx: Context, next: Next =>
            TagController.getById(ctx)
        })
    }

    router.group("/api/admin/tags") { adminTags =>
        adminTags.use(AuthMiddleware.requireAdminMiddleware())

        // 管理员接口：获取所有标签名（用于自动补全）
        adminTags.get("/names", { ctx: Context, next: Next =>
            TagController.adminListTagNames(ctx)
        })

        // 管理员接口：创建标签
        adminTags.post("", audited("tag.admin.create", { ctx: Context, next: Next =>
            TagController.adminCreate(ctx)
        }, riskLevel: 2))

        // 管理员接口：更新标签
        adminTags.put("/:id", audited("tag.admin.update", { ctx: Context, next: Next =>
            TagController.adminUpdate(ctx)
        }, riskLevel: 2))

        // 管理员接口：删除标签
        adminTags.delete("/:id", audited("tag.admin.delete", { ctx: Context, next: Next =>
            TagController.adminDelete(ctx)
        }, riskLevel: 2))

        // 管理员接口：导出标签
        adminTags.get("/export", { ctx: Context, next: Next =>
            TagController.adminExport(ctx)
        })

        // 管理员接口：分片上传导入
        adminTags.post("/import/init", audited("tag.admin.import.init", { ctx: Context, next: Next =>
            TagController.adminImportInit(ctx)
        }, riskLevel: 2))

        adminTags.put("/import/chunk", audited("tag.admin.import.chunk", { ctx: Context, next: Next =>
            TagController.adminImportUploadChunk(ctx)
        }, riskLevel: 3))

        adminTags.post("/import/complete", audited("tag.admin.import.complete", { ctx: Context, next: Next =>
            TagController.adminImportUploadComplete(ctx)
        }, riskLevel: 2))
    }
}