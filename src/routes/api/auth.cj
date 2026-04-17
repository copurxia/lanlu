package lanlu.routes.api

import ignite.*
import lanlu.contexts.user.interfaces.http.AuthController
import lanlu.contexts.user.interfaces.http.WebauthnController
import lanlu.contexts.user.interfaces.http.TotpController
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
    router.post("/api/auth/login", audited("auth.login", { ctx =>
        AuthController.login(ctx)
    }, riskLevel: 3))
    router.post("/api/auth/login/totp/verify", audited("auth.login.totp.verify", { ctx =>
        TotpController.loginVerify(ctx)
    }, riskLevel: 3))
    router.post("/api/auth/webauthn/authenticate/options", audited("auth.webauthn.authenticate.options", { ctx =>
        WebauthnController.authenticateOptions(ctx)
    }, riskLevel: 2))
    router.post("/api/auth/webauthn/authenticate/verify", audited("auth.webauthn.authenticate.verify", { ctx =>
        WebauthnController.authenticateVerify(ctx)
    }, riskLevel: 3))

    router.get("/api/auth/me", withUser({ ctx, userId => AuthController.me(ctx, userId) }))
    router.get("/api/auth/tokens", withUser({ ctx, userId => AuthController.listTokens(ctx, userId) }))
    router.get("/api/auth/sessions", withUser({ ctx, userId => AuthController.listSessions(ctx, userId) }))
    router.get("/api/auth/totp/status", withUser({ ctx, userId => TotpController.status(ctx, userId) }))
    router.get("/api/auth/webauthn/credentials", withUser({ ctx, userId => WebauthnController.listCredentials(ctx, userId) }))
    router.post("/api/auth/tokens", audited("auth.token.create", withUser({ ctx, userId => AuthController.createToken(ctx, userId) }), riskLevel: 3))
    router.post("/api/auth/totp/enroll/start", audited("auth.totp.enroll.start", withUser({ ctx, userId => TotpController.enrollStart(ctx, userId) }), riskLevel: 3))
    router.post("/api/auth/totp/enroll/confirm", audited("auth.totp.enroll.confirm", withUser({ ctx, userId => TotpController.enrollConfirm(ctx, userId) }), riskLevel: 3))
    router.post("/api/auth/totp/recovery-codes/regenerate", audited("auth.totp.recovery.regenerate", withUser({ ctx, userId => TotpController.regenerateRecoveryCodes(ctx, userId) }), riskLevel: 3))
    router.post("/api/auth/webauthn/register/options", audited("auth.webauthn.register.options", withUser({ ctx, userId => WebauthnController.registerOptions(ctx, userId) }), riskLevel: 2))
    router.post("/api/auth/webauthn/register/verify", audited("auth.webauthn.register.verify", withUser({ ctx, userId => WebauthnController.registerVerify(ctx, userId) }), riskLevel: 3))
    router.delete("/api/auth/totp", audited("auth.totp.disable", withUser({ ctx, userId => TotpController.disable(ctx, userId) }), riskLevel: 3))
    router.delete("/api/auth/webauthn/credentials/:id", audited("auth.webauthn.credential.revoke", withUser({ ctx, userId => WebauthnController.revokeCredential(ctx, userId) }), riskLevel: 3))
    router.delete("/api/auth/tokens/:id", audited("auth.token.revoke", withUser({ ctx, userId => AuthController.revokeToken(ctx, userId) }), riskLevel: 3))
    router.post("/api/auth/password", audited("auth.password.change", withUser({ ctx, userId => AuthController.changePassword(ctx, userId) }), riskLevel: 2))
    router.post("/api/auth/username", audited("auth.username.change", withUser({ ctx, userId => AuthController.changeUsername(ctx, userId) }), riskLevel: 3))

    // ===== 用户管理接口（仅管理员可访问）=====
    router.get("/api/auth/admin/users", withAdmin({ ctx => AuthController.listUsers(ctx) }))
    router.post("/api/auth/admin/users", audited("auth.admin.user.create", withAdmin({ ctx => AuthController.createUser(ctx) }), riskLevel: 2))
    router.put("/api/auth/admin/users/:id/role", audited("auth.admin.user.role.update", withAdmin({ ctx => AuthController.updateUserRole(ctx) }), riskLevel: 2))
    router.delete("/api/auth/admin/users/:id", audited("auth.admin.user.delete", withAdminUser({ ctx, userId => AuthController.deleteUser(ctx, userId) }), riskLevel: 2))
    router.post("/api/auth/admin/users/:id/reset-password", audited("auth.admin.user.password.reset", withAdmin({ ctx => AuthController.resetUserPassword(ctx) }), riskLevel: 2))
}
