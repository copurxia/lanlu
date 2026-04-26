package lanlu.contexts.task

/**
 * Strongly typed task lifecycle state.
 *
 * Database and API payloads still use strings. Keep conversion here so the
 * rest of the code can express lifecycle rules through the type instead of
 * repeated string comparisons.
 */
public enum TaskStatus {
    | Pending
    | Running
    | Waiting
    | Completed
    | Failed
    | Stopped
    | Unknown(String)

    public static func fromDb(value: String): TaskStatus {
        match (value.trimAscii()) {
            case "pending" => return Pending
            case "running" => return Running
            case "waiting" => return Waiting
            case "completed" => return Completed
            case "failed" => return Failed
            case "stopped" => return Stopped
            case _ => return Unknown(value.trimAscii())
        }
    }

    public static func isValidDbValue(value: String): Bool {
        return TaskStatus.fromDb(value).isKnown()
    }

    public static func defaultPhaseForDbValue(value: String): String {
        return TaskStatus.fromDb(value).defaultPhase()
    }

    public func toDb(): String {
        match (this) {
            case Pending => return "pending"
            case Running => return "running"
            case Waiting => return "waiting"
            case Completed => return "completed"
            case Failed => return "failed"
            case Stopped => return "stopped"
            case Unknown(value) => return value
        }
    }

    public func isKnown(): Bool {
        match (this) {
            case Unknown(_) => return false
            case _ => return true
        }
    }

    public func isTerminal(): Bool {
        match (this) {
            case Completed => return true
            case Failed => return true
            case Stopped => return true
            case _ => return false
        }
    }

    public func isPending(): Bool {
        match (this) {
            case Pending => return true
            case _ => return false
        }
    }

    public func isCompleted(): Bool {
        match (this) {
            case Completed => return true
            case _ => return false
        }
    }

    public func isCancellable(): Bool {
        match (this) {
            case Pending => return true
            case Running => return true
            case Waiting => return true
            case _ => return false
        }
    }

    public func isRetryable(): Bool {
        match (this) {
            case Failed => return true
            case Stopped => return true
            case _ => return false
        }
    }

    public func defaultPhase(): String {
        match (this) {
            case Pending => return "queued"
            case Running => return "executing"
            case Waiting => return "waiting"
            case Completed => return "completed"
            case Failed => return "failed"
            case Stopped => return "stopped"
            case Unknown(_) => return ""
        }
    }
}
