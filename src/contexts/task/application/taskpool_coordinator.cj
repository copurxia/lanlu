package lanlu.contexts.task.application

import std.collection.*
import std.sync.*
import std.time.*
import stdx.log.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*

/**
 * Single owner of TaskPool scheduling state.
 */
public class TaskPoolCoordinator {
    private static let orphanReconcileIntervalMillis: Int64 = 60000
    private static let orphanMinRunningAgeMillis: Int64 = 120000

    private let mailbox: TaskPoolMailbox

    private let lifecycleMutex: Mutex
    private var isRunning: Bool
    private var loopStarted: Bool
    private var shutdownRequested: Bool
    private var loopFuture: Option<Future<Unit>>

    private var maxWorkers: Int32
    private var currentWorkers: Int32
    private var workerSeq: Int32
    private var activeWorkers: HashMap<Int64, Int32>
    private var lastOrphanReconcileAtMs: Int64
    private var claimInProgress: Bool

    private let registry: TaskRunnerRegistry
    private let pipeline: TaskExecutionPipeline
    private var executor: Option<TaskWorkerExecutor>

    public init() {
        mailbox = TaskPoolMailbox()

        lifecycleMutex = Mutex()
        isRunning = false
        loopStarted = false
        shutdownRequested = false
        loopFuture = Option<Future<Unit>>.None

        maxWorkers = 2
        currentWorkers = 0
        workerSeq = 0
        activeWorkers = HashMap<Int64, Int32>()
        lastOrphanReconcileAtMs = 0
        claimInProgress = false

        registry = TaskRunnerRegistry()
        pipeline = TaskExecutionPipeline(registry)
        executor = Option<TaskWorkerExecutor>.None
        executor = Some(TaskWorkerExecutor(
            pipeline,
            { result: TaskWorkerResult => this.enqueue(TaskPoolEvent.WorkerFinished(result.taskId, result.workerId)) },
            { => this.enqueue(TaskPoolEvent.TaskAvailable) },
            { => this.enqueue(TaskPoolEvent.TaskAvailable) }
        ))
        loadMaxWorkersConfig()
    }

    public func start(): Bool {
        lifecycleMutex.lock()
        if (isRunning) {
            lifecycleMutex.unlock()
            return true
        }
        isRunning = true
        shutdownRequested = false
        let shouldStartLoop = !loopStarted
        if (shouldStartLoop) {
            loopStarted = true
        }
        lifecycleMutex.unlock()

        if (shouldStartLoop) {
            let future = spawn {
                runEventLoop()
            }
            lifecycleMutex.lock()
            loopFuture = Some(future)
            lifecycleMutex.unlock()
        }

        let logger = getLogger("taskpool")
        logger.debug("TaskPool starting", ("max_workers", maxWorkers.toString()))
        enqueue(TaskPoolEvent.Start)
        return true
    }

    public func stop(): Unit {
        lifecycleMutex.lock()
        if (!isRunning) {
            lifecycleMutex.unlock()
            return
        }
        isRunning = false
        lifecycleMutex.unlock()
        enqueue(TaskPoolEvent.Shutdown)
    }

    public func isServiceRunning(): Bool {
        lifecycleMutex.lock()
        let running = isRunning
        lifecycleMutex.unlock()
        return running
    }

    public func isCoordinatorLoopAlive(): Bool {
        lifecycleMutex.lock()
        let futureOpt = loopFuture
        lifecycleMutex.unlock()
        match (futureOpt) {
            case Some(future) =>
                try {
                    match (future.tryGet()) {
                        case Some(_) => return false
                        case None => return true
                    }
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public func notifyTaskAvailable(): Unit {
        if (!isServiceRunning()) {
            return
        }
        enqueue(TaskPoolEvent.TaskAvailable)
    }

    public func safetyTick(): Unit {
        if (!isServiceRunning()) {
            return
        }
        enqueue(TaskPoolEvent.SafetyTick)
    }

    public func reloadMaxWorkersConfig(): Unit {
        if (!isServiceRunning()) {
            loadMaxWorkersConfig()
            return
        }
        enqueue(TaskPoolEvent.ReloadMaxWorkersConfig)
    }

    public func supportedTaskTypes(): Array<String> {
        return registry.supportedTaskTypes()
    }

    private func enqueue(event: TaskPoolEvent): Unit {
        mailbox.put(event)
    }

    private func runEventLoop(): Unit {
        while (true) {
            let shouldContinue = handleEvent(mailbox.take())
            if (!shouldContinue) {
                markLoopStopped()
                return
            }
        }
    }

    private func markLoopStopped(): Unit {
        lifecycleMutex.lock()
        loopStarted = false
        loopFuture = Option<Future<Unit>>.None
        lifecycleMutex.unlock()
    }

    private func handleEvent(event: TaskPoolEvent): Bool {
        match (event) {
            case Start =>
                dispatchUntilFull()
                return true
            case TaskAvailable =>
                dispatchUntilFull()
                return true
            case SafetyTick =>
                reconcileOrphanedRunningTasks()
                dispatchUntilFull()
                return true
            case ClaimCompleted(tasks) =>
                handleClaimCompleted(tasks)
                if (shutdownRequested && currentWorkers == 0 && !claimInProgress) {
                    getLogger("taskpool").debug("TaskPool coordinator stopped after claim drained")
                    return false
                }
                dispatchUntilFull()
                return true
            case WorkerFinished(taskId, workerId) =>
                handleWorkerFinished(taskId, workerId)
                if (shutdownRequested && currentWorkers == 0 && !claimInProgress) {
                    getLogger("taskpool").debug("TaskPool coordinator stopped after workers drained")
                    return false
                }
                dispatchUntilFull()
                return true
            case ReloadMaxWorkersConfig =>
                reloadMaxWorkersConfigNow()
                dispatchUntilFull()
                return true
            case ReconcileRequested =>
                reconcileOrphanedRunningTasks()
                dispatchUntilFull()
                return true
            case Shutdown =>
                shutdownRequested = true
                if (currentWorkers == 0 && !claimInProgress) {
                    getLogger("taskpool").debug("TaskPool coordinator stopped")
                    return false
                }
                getLogger("taskpool").debug(
                    "TaskPool coordinator waiting for claim or workers before stop",
                    ("current_workers", currentWorkers.toString())
                )
                return true
        }
    }

    private func loadMaxWorkersConfig(): Unit {
        let workersInt = SystemSettingsService.getInt("MAX_CONCURRENT_JOBS")
        maxWorkers = if (workersInt > 0) {
            workersInt
        } else {
            2
        }
        if (maxWorkers < 1) {
            maxWorkers = 1
        }
    }

    private func reloadMaxWorkersConfigNow(): Unit {
        let logger = getLogger("taskpool")
        let oldMaxWorkers = maxWorkers
        loadMaxWorkersConfig()
        logger.debug(
            "TaskPool config reloaded",
            ("old_max_workers", oldMaxWorkers.toString()),
            ("new_max_workers", maxWorkers.toString())
        )
    }

    private func dispatchUntilFull(): Unit {
        if (!isServiceRunning()) {
            return
        }
        if (claimInProgress) {
            return
        }
        let available = maxWorkers - currentWorkers
        if (available <= 0) {
            return
        }
        claimInProgress = true
        spawn {
            let tasks = TaskDao.claimPendingTasks(available)
            this.enqueue(TaskPoolEvent.ClaimCompleted(tasks))
        }
    }

    private func handleClaimCompleted(tasks: ArrayList<TaskData>): Unit {
        claimInProgress = false
        if (tasks.size == 0) {
            return
        }
        let logger = getLogger("taskpool")
        let workerExecutor = match (executor) {
            case Some(e) => e
            case None => return
        }

        logger.debug(
            "TaskPool dispatch claimed tasks",
            ("current_workers", currentWorkers.toString()),
            ("available_slots", (maxWorkers - currentWorkers).toString()),
            ("claimed_count", tasks.size.toString())
        )

        for (task in tasks) {
            if (activeWorkers.contains(task.id)) {
                logger.error(
                    "double-claim detected: task already has an active worker, skip re-dispatch",
                    ("task_id", task.id.toString()),
                    ("task_type", task.taskType)
                )
                continue
            }
            currentWorkers += 1
            let workerId = workerSeq
            workerSeq += 1
            activeWorkers[task.id] = workerId
            workerExecutor.start(task, workerId)
        }
    }

    private func handleWorkerFinished(taskId: Int64, workerId: Int32): Unit {
        let logger = getLogger("taskpool")
        if (taskId <= 0) {
            logger.warn("TaskPool worker finished with invalid task id", ("worker", workerId.toString()))
            return
        }

        match (activeWorkers.get(taskId)) {
            case Some(activeWorkerId) =>
                if (activeWorkerId != workerId) {
                    logger.warn(
                        "Ignore stale TaskPool worker completion",
                        ("worker", workerId.toString()),
                        ("active_worker", activeWorkerId.toString()),
                        ("task_id", taskId.toString())
                    )
                    return
                }
                let _ = activeWorkers.remove(taskId)
            case None =>
                logger.warn(
                    "Ignore duplicate or unknown TaskPool worker completion",
                    ("worker", workerId.toString()),
                    ("task_id", taskId.toString()),
                    ("current_workers", currentWorkers.toString())
                )
                return
        }

        if (currentWorkers > 0) {
            currentWorkers -= 1
        } else {
            logger.warn(
                "TaskPool worker accounting underflow avoided",
                ("worker", workerId.toString()),
                ("task_id", taskId.toString())
            )
        }
        logger.debug(
            "TaskPool worker released",
            ("worker", workerId.toString()),
            ("task_id", taskId.toString()),
            ("current_workers", currentWorkers.toString())
        )
    }

    private func reconcileOrphanedRunningTasks(): Unit {
        let logger = getLogger("taskpool")
        if (!shouldRunOrphanReconcile()) {
            return
        }
        let runningTasks = TaskDao.getTasksWithPaginationByStatus(0, 512, "running")
        let now = DateTime.now()
        for (task in runningTasks) {
            if (task.id <= 0 || activeWorkers.contains(task.id)) {
                continue
            }
            if (!isTaskOldEnoughForOrphanCheck(task, now)) {
                continue
            }
            if (TaskIO.readOutput(task.id, maxBytes: 256).trimAscii().size > 0) {
                logger.warn(
                    "Skip orphan recovery because task already has output",
                    ("task_id", task.id.toString()),
                    ("task_type", task.taskType),
                    ("phase", task.phase)
                )
                continue
            }

            let latestTask = TaskDao.getTaskDataById(task.id)
            if (latestTask.id == 0 || latestTask.status != "running" || activeWorkers.contains(latestTask.id)) {
                continue
            }
            if (!isTaskOldEnoughForOrphanCheck(latestTask, now)) {
                continue
            }
            if (TaskIO.readOutput(latestTask.id, maxBytes: 256).trimAscii().size > 0) {
                logger.warn(
                    "Skip orphan recovery after recheck because task already has output",
                    ("task_id", latestTask.id.toString()),
                    ("task_type", latestTask.taskType),
                    ("phase", latestTask.phase)
                )
                continue
            }

            logger.error(
                "Detected orphaned running task",
                ("task_id", latestTask.id.toString()),
                ("task_type", latestTask.taskType),
                ("phase", latestTask.phase),
                ("started_at", latestTask.startedAt)
            )
            TaskIO.appendLog(latestTask.id, "ERROR: task worker lost; marking task failed")
            if (TaskModel.failTask(latestTask.id, "Task worker lost")) {
                triggerDependentTasks(latestTask.id)
            }
        }
    }

    private func triggerDependentTasks(completedTaskId: Int64): Unit {
        let logger = getLogger("taskpool")
        let completedTask = TaskDao.getTaskDataById(completedTaskId)
        if (completedTask.id == 0) {
            return
        }

        let waitingTasks = TaskDao.getTasksWaitingFor(completedTaskId)
        if (waitingTasks.size == 0) {
            return
        }

        logger.debug(
            "触发依赖任务",
            ("completed_id", completedTaskId.toString()),
            ("waiting_count", waitingTasks.size.toString())
        )

        for (waitingTask in waitingTasks) {
            TaskDao.activateWaitingTask(waitingTask.id)
            logger.debug(
                "激活等待任务",
                ("id", waitingTask.id.toString()),
                ("wait_for_status", completedTask.status)
            )
        }
        enqueue(TaskPoolEvent.TaskAvailable)
    }

    private func shouldRunOrphanReconcile(): Bool {
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        if ((nowMs - lastOrphanReconcileAtMs) < TaskPoolCoordinator.orphanReconcileIntervalMillis) {
            return false
        }
        lastOrphanReconcileAtMs = nowMs
        return true
    }

    private func isTaskOldEnoughForOrphanCheck(task: TaskData, now: DateTime): Bool {
        let baseline = if (task.startedAt.trimAscii().size > 0) { task.startedAt } else { task.createdAt }
        if (baseline.trimAscii().size == 0) {
            return false
        }
        match (DateTime.tryParse(baseline)) {
            case Some(started) =>
                let ageMs = (now - started).toMilliseconds()
                return ageMs >= TaskPoolCoordinator.orphanMinRunningAgeMillis
            case None =>
                return false
        }
    }
}
