package lanlu.models

import lanlu.dao.*
import lanlu.utils.*
import lanlu.config.*

public class UserModel {
    /**
     * 初始化用户认证（检查并创建默认管理员）
     * 注意：表创建已由迁移系统处理
     */
    public static func initialize(): Bool {
        let logger = getLogger("user_model")
        logger.debug("初始化用户认证")

        // 检查是否需要创建默认管理员
        logger.debug("检查用户表是否为空")
        let isEmpty = UserDao.isEmpty()
        logger.debug("用户表为空检查结果: ${isEmpty}")

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

        logger.debug("用户认证初始化完成")
        return true
    }
}
