python3 := "python3"

doctor:
    {{python3}} -m tools.xtask doctor --json

plan base="HEAD" *args:
    {{python3}} -m tools.xtask plan --github-matrix --base {{base}} {{args}}

test *args:
    {{python3}} -m tools.xtask test --changed {{args}}

ci:
    {{python3}} -m tools.xtask doctor
    {{python3}} -m tools.xtask test --changed
    {{python3}} -m tools.xtask gate-result --summary target/test-results/summary.json
