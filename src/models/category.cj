package lanlu.models

/**
 * 分类数据模型（新结构）
 * 每个分类对应一个扫描目录
 */
public class Category {
    public var id: String = ""           // catid
    public var internalId: Int64 = 0     // 数据库内部 ID
    public var name: String = ""
    public var scanPath: String = ""     // 扫描目录路径
    public var description: String = ""
    public var icon: String = ""
    public var sortOrder: Int32 = 0
    public var enabled: Bool = true
    public var plugins: String = "[]"    // 启用的元数据插件列表 (JSON数组)
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var archiveCount: Int64 = 0   // 分类下的档案数量
}
