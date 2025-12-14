package lrr4cj.models

import lrr4cj.dao.*
import lrr4cj.utils.*
import lrr4cj.config.*

public class UserModel {
    public static func initialize(): Bool {
        let logger = getLogger("user_model")
        logger.info("初始化用户认证相关表")

        let usersOk = UserDao.createTable()
        if (!usersOk) {
            logger.error("创建 users 表失败")
            return false
        }

        let tokensOk = UserTokenDao.createTable()
        if (!tokensOk) {
            logger.error("创建 user_tokens 表失败")
            return false
        }

        // 如果用户表为空，创建默认管理员
        if (UserDao.isEmpty()) {
            let defaultUsername = "admin"
            let defaultPassword = AuthUtils.generateTokenHex(bytesLen: 8) // 16位随机密码

            match (UserDao.createUser(defaultUsername, defaultPassword, AuthConfig.tokenPepper)) {
                case Some(userId) =>
                    logger.info("========================================")
                    logger.info("已创建默认管理员账户")
                    logger.info("用户名: ${defaultUsername}")
                    logger.info("密码: ${defaultPassword}")
                    logger.info("请登录后立即修改密码！")
                    logger.info("========================================")
                case None =>
                    logger.error("创建默认管理员账户失败")
                    return false
            }
        }

        return true
    }
}
