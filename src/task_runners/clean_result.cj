package lanlu.task_runners

import std.collection.*

/**
 * Shared cleanup stats for task runners that delete files/directories.
 */
public class CleanResult {
    public var deletedCount: Int64
    public var deletedSize: Int64
    public var skippedCount: Int64
    public var errors: ArrayList<String>

    public init() {
        this.deletedCount = 0
        this.deletedSize = 0
        this.skippedCount = 0
        this.errors = ArrayList<String>()
    }
}

