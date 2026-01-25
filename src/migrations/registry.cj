package lanlu.migrations

import std.collection.*
import std.sort.*

/**
 * 迁移注册中心 - 收集所有迁移并按版本排序
 */
public class MigrationRegistry {
    private static var migrations = ArrayList<Migration>()

    /**
     * 注册一个迁移
     */
    public static func register(m: Migration): Unit {
        migrations.add(m)
    }

    /**
     * 获取所有注册的迁移，按版本号排序
     */
    public static func getAll(): ArrayList<Migration> {
        // 按版本号排序
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

    /**
     * 获取注册的迁移数量
     */
    public static func count(): Int64 {
        return migrations.size
    }
}
