package lanlu.routes.api.auth

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

public func registerAuthRoutes(router: JoyRouters) {
    // 注册接口：需要已登录用户才能创建新用户
    router.post("/api/auth/register", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(_) => AuthController.register(ctx)
            case None => return
        }
    })

    router.post("/api/auth/login", { ctx =>
        AuthController.login(ctx)
    })

    router.get("/api/auth/me", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.me(ctx, userId)
            case None => return
        }
    })

    router.get("/api/auth/tokens", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.listTokens(ctx, userId)
            case None => return
        }
    })

    router.get("/api/auth/sessions", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.listSessions(ctx, userId)
            case None => return
        }
    })

    router.post("/api/auth/tokens", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.createToken(ctx, userId)
            case None => return
        }
    })

    router.delete("/api/auth/tokens/{id}", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.revokeToken(ctx, userId)
            case None => return
        }
    })

    router.post("/api/auth/password", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.changePassword(ctx, userId)
            case None => return
        }
    })

    router.post("/api/auth/username", { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => AuthController.changeUsername(ctx, userId)
            case None => return
        }
    })

    // ===== 用户管理接口（仅管理员可访问）=====

    router.get("/api/auth/admin/users", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => AuthController.listUsers(ctx)
            case None => return
        }
    })

    router.post("/api/auth/admin/users", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => AuthController.createUser(ctx)
            case None => return
        }
    })

    router.put("/api/auth/admin/users/{id}/role", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => AuthController.updateUserRole(ctx)
            case None => return
        }
    })

    router.delete("/api/auth/admin/users/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(userId) => AuthController.deleteUser(ctx, userId)
            case None => return
        }
    })

    router.post("/api/auth/admin/users/{id}/reset-password", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => AuthController.resetUserPassword(ctx)
            case None => return
        }
    })
}

