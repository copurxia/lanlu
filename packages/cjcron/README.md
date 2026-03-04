# cjcron

`cjcron` is a small Cangjie cron expression parser and next-run calculator.

## Supported syntax (v0.1.0)

- 5-field cron: `min hour dom mon dow`
- Optional 6-field cron: `sec min hour dom mon dow`
- Lists `,`, ranges `-`, steps `/`, wildcard `*`
- Month names: `JAN`..`DEC` (case-insensitive)
- Day-of-week names: `SUN`..`SAT` (case-insensitive, `0`/`7` = Sunday)
- Aliases: `@yearly`, `@monthly`, `@weekly`, `@daily`, `@hourly`

Timezone: computed using the `DateTime` instance's timezone (Local by default).

## Usage

```cangjie
import cjcron.*
import std.time.*

let expr = CronExpression.parse("0 */6 * * *")
let now = DateTime.now()
let next = expr.next(after: now)
```

