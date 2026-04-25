package lanlu.contexts.task.application.runners

import stdx.log.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.shared.utils.*

/**
 * Placeholder upload runner.
 *
 * The HTTP upload flow performs the actual chunk writes. This runner only keeps
 * a TaskPool worker slot occupied until the upload session reaches a terminal
 * state, so upload concurrency remains governed by TaskPool.
 */
public class UploadPlaceholderTaskRunner {
    private static let uploadIdleTimeoutSeconds: Int32 = 600
    private static let uploadWaitHeartbeatMillis: Int64 = 15000

    public static func run(taskId: Int64, placeholderTaskType: String): Unit {
        let _ = TaskDao.extendTaskTimeout(taskId, uploadIdleTimeoutSeconds)
        TaskIO.appendLog(taskId, "${placeholderTaskType} task is now running, waiting for complete/failed")
        waitFinalization(taskId, placeholderTaskType)
    }

    private static func waitFinalization(taskId: Int64, placeholderTaskType: String): Unit {
        let logger = getLogger("taskpool")
        let eventHub = TaskEventHub.getInstance()
        var ticks: Int64 = 0
        var revision = eventHub.currentRevision(taskId)

        while (true) {
            let task = TaskDao.getTaskDataById(taskId)
            if (task.id == 0) {
                TaskIO.appendLog(taskId, "${placeholderTaskType} task missing while waiting; stop waiting")
                return
            }

            if (task.phase == "handoff_completed" || task.phase == "phase_completed") {
                TaskIO.appendLog(taskId, "${placeholderTaskType} task phase completed; release worker")
                return
            }

            if (isTerminalStatus(task.status)) {
                TaskIO.appendLog(taskId, "${placeholderTaskType} task reached terminal status: ${task.status}")
                return
            }

            let stableRevision = eventHub.currentRevision(taskId)
            if (stableRevision != revision) {
                revision = stableRevision
                continue
            }

            let waitResult = eventHub.awaitNext(taskId, revision, uploadWaitHeartbeatMillis)
            revision = waitResult.revision
            if (!waitResult.changed) {
                ticks += 1
            }
            if (ticks > 0 && ticks % 30 == 0) {
                logger.debug(
                    "${placeholderTaskType} task still running",
                    ("task_id", taskId.toString()),
                    ("status", task.status),
                    ("phase", task.phase),
                    ("progress", task.progress.toString())
                )
            }
        }
    }

    private static func isTerminalStatus(status: String): Bool {
        return status == "completed" || status == "failed" || status == "stopped"
    }
}
