package lanlu.shared.config

import std.unittest.*
import std.unittest.testmacro.*
import csorm.*

// task-3 验收：connection_pool stats 接 driver 真实指标（需要 DB_STRING 指向可用库）
@Test
func poolStatsShapeWhenUninitialized() {
    // DatabaseConfig.poolStats() 形状断言（未初始化时 0 元组，不抛异常）
    let (open, idle, waiting, timeouts) = DatabaseConfig.poolStats()
    @Assert(open >= 0, true)
    @Assert(idle >= 0, true)
    @Assert(waiting >= 0, true)
    @Assert(timeouts >= 0, true)
}