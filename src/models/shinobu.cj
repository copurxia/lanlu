package lanlu.models

/**
 * Shinobu状态数据模型
 */
public class ShinobuStatus {
    public var success: Int32
    public var isAlive: Int32
    public var operation: String
    public var pid: Int64
    
    public init(success: Int32, isAlive: Int32, operation: String, pid: Int64) {
        this.success = success
        this.isAlive = isAlive
        this.operation = operation
        this.pid = pid
    }
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return "{\"success\":${success},\"is_alive\":${isAlive},\"operation\":\"${operation}\",\"pid\":${pid}}"
    }
}

/**
 * Shinobu操作结果数据模型
 */
public class ShinobuResult {
    public var success: Int32
    public var operation: String
    public var newPid: Int64
    
    public init(success: Int32, operation: String, newPid: Int64) {
        this.success = success
        this.operation = operation
        this.newPid = newPid
    }
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return "{\"success\":${success},\"operation\":\"${operation}\",\"new_pid\":${newPid}}"
    }
}


