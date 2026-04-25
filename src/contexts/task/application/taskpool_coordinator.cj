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

    private let eventMutex: Mutex
    private let eventCond: Condition
    private var events: ArrayList<TaskPoolEvent>

    private let lifecycleMutex: Mutex
    private var isRunning: Bool
    private var loopStarted: Bool

    private var maxWorkers: Int32
    private var currentWorkers: Int32
    private var workerSeq: Int32
    private var activeWorkers: HashMap<Int64, Int32>
    private var lastOrphanReconcileAtMs: Int64

    private let registry: TaskRunnerRegistry
    private let pipeline: TaskExecutionPipeline
    private var executor: Option<TaskWorkerExecutor>

    public init() {
        eventMutex = Mutex()
        eventMutex.lock()
        eventCond = eventMutex.condition()
        eventMutex.unlock()
        events = ArrayList<TaskPoolEvent>()

        lifecycleMutex = Mutex()
        isRunning = false
        loopStarted = false

        maxWorkers = 2
        currentWorkers = 0
        workerSeq = 0
        activeWorkers = HashMap<Int64, Int32>()
        lastOrphanReconcileAtMs = 0

        registry = TaskRunnerRegistry()
        pipeline = TaskExecutionPipeline(registry)
        executor = Option<TaskWorkerExecutor>.None
        executor = Some(TaskWorkerExecutor(
            pipeline,
            { result: TaskWorkerResult => this.enqueue(TaskPoolEvent.workerFinished(result.taskId, result.workerId)) },
            { => this.enqueue(TaskPoolEvent.taskAvailable()) },
            { => this.enqueue(TaskPoolEvent.taskAvailable()) }
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
        let shouldStartLoop = !loopStarted
        if (shouldStartLoop) {
            loopStarted = true
        }
        lifecycleMutex.unlock()

        if (shouldStartLoop) {
            spawn {
                runEventLoop()
            }
        }

        let logger = getLogger("taskpool")
        logger.debug("TaskPool starting", ("max_workers", maxWorkers.toString()))
        enqueue(TaskPoolEvent.start())
        return true
    }

    public func isServiceRunning(): Bool {
        lifecycleMutex.lock()
        let running = isRunning
        lifecycleMutex.unlock()
        return running
    }

    public func notifyTaskAvailable(): Unit {
        if (!isServiceRunning()) {
            return
        }
        enqueue(TaskPoolEvent.taskAvailable())
    }

    public func safetyTick(): Unit {
        if (!isServiceRunning()) {
            return
        }
        enqueue(TaskPoolEvent.safetyTick())
    }

    public func reloadMaxWorkersConfig(): Unit {
        if (!isServiceRunning()) {
            loadMaxWorkersConfig()
            return
        }
        enqueue(TaskPoolEvent.reloadMaxWorkersConfig())
    }

    public func supportedTaskTypes(): Array<String> {
        return registry.supportedTaskTypes()
    }

    private func enqueue(event: TaskPoolEvent): Unit {
        eventMutex.lock()
        events.add(event)
        eventCond.notifyAll()
        eventMutex.unlock()
    }

    private func runEventLoop(): Unit {
        while (true) {
            let event = takeEvent()
            handleEvent(event)
        }
    }

    private func takeEvent(): TaskPoolEvent {
        eventMutex.lock()
        try {
            let _ = eventCond.waitUntil({ => events.size > 0 })
            return events.remove(at: 0)
        } finally {
            eventMutex.unlock()
        }
    }

    private func handleEvent(event: TaskPoolEvent): Unit {
        match (event.eventType) {
            case "start" =>
                dispatchUntilFull()
            case "task_available" =>
                dispatchUntilFull()
            case "safety_tick" =>
                reconcileOrphanedRunningTasks()
                dispatchUntilFull()
            case "worker_finished" =>
                handleWorkerFinished(event.taskId, event.workerId)
                dispatchUntilFull()
            case "reload_max_workers_config" =>
                reloadMaxWorkersConfigNow()
                dispatchUntilFull()
            case "reconcile_requested" =>
                reconcileOrphanedRunningTasks()
                dispatchUntilFull()
            case _ => ()
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
        let logger = getLogger("taskpool")
        if (!isServiceRunning()) {
            return
        }
        let workerExecutor = match (executor) {
            case Some(e) => e
            case None => return
        }

        reconcileOrphanedRunningTasks()

        while (isServiceRunning()) {
            let available = maxWorkers - currentWorkers
            if (available <= 0) {
                return
            }

            let tasks = TaskDao.claimPendingTasks(available)
            if (tasks.size == 0) {
                return
            }

            logger.debug(
                "TaskPool dispatch claimed tasks",
                ("current_workers", currentWorkers.toString()),
                ("available_slots", available.toString()),
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
    }

    private func handleWorkerFinished(taskId: Int64, workerId: Int32): Unit {
        if (taskId > 0) {
            let _ = activeWorkers.remove(taskId)
        }
        if (currentWorkers > 0) {
            currentWorkers -= 1
        }
        getLogger("taskpool").debug(
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
        enqueue(TaskPoolEvent.taskAvailable())
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
