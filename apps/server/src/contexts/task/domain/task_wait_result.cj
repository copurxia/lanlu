package lanlu.contexts.task.domain

/**
 * 任务等待结果
 */
public class TaskWaitResult {
    public var success: Bool = false
    public var error: String = ""
    public var output: String = ""

    public init(success: Bool, error: String, output: String) {
        this.success = success
        this.error = error
        this.output = output
    }
}
