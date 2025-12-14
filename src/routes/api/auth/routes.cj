package lrr4cj.routes.api.auth

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

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
}

