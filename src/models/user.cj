package lrr4cj.models

import lrr4cj.dao.*
import lrr4cj.utils.*
import lrr4cj.config.*

public class UserModel {
    public static func initialize(): Bool {
        let logger = getLogger("user_model")
        logger.info("初始化用户认证相关表")

        // 步骤1: 创建或更新 users 表
        logger.info("开始创建或更新 users 表")
        let usersOk = UserDao.createTable()
        if (!usersOk) {
            logger.error("创建 users 表失败")
            return false
        }
        logger.info("users 表创建或更新成功")

        // 步骤2: 创建或更新 user_tokens 表
        logger.info("开始创建或更新 user_tokens 表")
        let tokensOk = UserTokenDao.createTable()
        if (!tokensOk) {
            logger.error("创建 user_tokens 表失败")
            return false
        }
        logger.info("user_tokens 表创建或更新成功")

        // 步骤3: 检查是否需要创建默认管理员
        logger.info("检查用户表是否为空")
        let isEmpty = UserDao.isEmpty()
        logger.info("用户表为空检查结果: ${isEmpty}")

        if (isEmpty) {
            let defaultUsername = "admin"
            let defaultPassword = AuthUtils.generateTokenHex(bytesLen: 8) // 16位随机密码

            logger.info("开始创建默认管理员账户")
            match (UserDao.createUser(defaultUsername, defaultPassword, AuthConfig.tokenPepper, true)) {
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
        } else {
            logger.info("用户表不为空，跳过创建默认管理员")
        }

        logger.info("用户认证相关表初始化完成")
        return true
    }
}
