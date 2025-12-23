import cjcron.*
import std.time.*

main(): Int64 {
    let expr = CronExpression.parse("0 */6 * * *")
    let now = DateTime.now()
    match (expr.next(after: now)) {
        case Some(dt) =>
            println("now=${now} next=${dt}")
        case None =>
            println("no next run found")
    }
    return 0
}

