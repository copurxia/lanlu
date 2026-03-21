package lanlu.routes.api

import ignite.*
import lanlu.contexts.user.interfaces.http.AuthController
import lanlu.infrastructure.middleware.*

private func withUser(action: (Ctx, Int64) -> Unit): Handler {
    { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => action(ctx, userId)
            case None => return
        }
    }
}

private func withAdminUser(action: (Ctx, Int64) -> Unit): Handler {
    { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(userId) => action(ctx, userId)
            case None => return
        }
    }
}

private func withAdmin(action: (Ctx) -> Unit): Handler {
    { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => action(ctx)
            case None => return
        }
    }
}

public func registerAuthRoutes(router: App) {
    router.post("/api/auth/login", { ctx =>
        AuthController.login(ctx)
    })

    router.get("/api/auth/me", withUser({ ctx, userId => AuthController.me(ctx, userId) }))
    router.get("/api/auth/tokens", withUser({ ctx, userId => AuthController.listTokens(ctx, userId) }))
    router.get("/api/auth/sessions", withUser({ ctx, userId => AuthController.listSessions(ctx, userId) }))
    router.post("/api/auth/tokens", withUser({ ctx, userId => AuthController.createToken(ctx, userId) }))
    router.delete("/api/auth/tokens/:id", withUser({ ctx, userId => AuthController.revokeToken(ctx, userId) }))
    router.post("/api/auth/password", withUser({ ctx, userId => AuthController.changePassword(ctx, userId) }))
    router.post("/api/auth/username", withUser({ ctx, userId => AuthController.changeUsername(ctx, userId) }))

    // ===== 用户管理接口（仅管理员可访问）=====
    router.get("/api/auth/admin/users", withAdmin({ ctx => AuthController.listUsers(ctx) }))
    router.post("/api/auth/admin/users", withAdmin({ ctx => AuthController.createUser(ctx) }))
    router.put("/api/auth/admin/users/:id/role", withAdmin({ ctx => AuthController.updateUserRole(ctx) }))
    router.delete("/api/auth/admin/users/:id", withAdminUser({ ctx, userId => AuthController.deleteUser(ctx, userId) }))
    router.post("/api/auth/admin/users/:id/reset-password", withAdmin({ ctx => AuthController.resetUserPassword(ctx) }))
}
