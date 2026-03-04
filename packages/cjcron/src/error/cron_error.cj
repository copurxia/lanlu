package cjcron.error

public class CronError <: Exception {
    public init(message: String) {
        super(message)
    }
}

