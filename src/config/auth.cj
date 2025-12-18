package lrr4cj.config

import dotenv.Dotenv

/**
 * 认证相关配置
 */
public class AuthConfig {
    public static var tokenPepper: String

    static init() {
        let config = Dotenv.createConfig()
        // 复用现有 JWT_SECRET 作为 pepper，避免将 token/hash 直接暴露为可离线撞库的 SHA256(token)
        tokenPepper = config.read("JWT_SECRET", "")
    }
}

