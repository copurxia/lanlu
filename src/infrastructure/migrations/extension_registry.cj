package lanlu.infrastructure.migrations

import std.collection.*
import std.sort.*

/**
 * 扩展迁移注册中心 - 收集依赖数据库扩展的迁移并按版本排序
 */
public class ExtensionMigrationRegistry {
    private static var migrations = ArrayList<ExtensionMigration>()

    /**
     * 注册一个扩展迁移
     */
    public static func register(m: ExtensionMigration): Unit {
        migrations.add(m)
    }

    /**
     * 获取所有注册的扩展迁移，按版本号排序
     */
    public static func getAll(): ArrayList<ExtensionMigration> {
        sort(migrations, by: { a, b =>
            if (a.version() < b.version()) {
                Ordering.LT
            } else if (a.version() > b.version()) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        return migrations
    }
}
