package ffi_probe

// 最小"引擎"：调用壳导出的 C 函数（历史崩溃场景），并导出两个 @C 入口。
foreign func lwp_probe(x: Int32): Int32
foreign func lwp_spawn_foreign(): Int32

// 导出给壳：外部线程会调它（验证"外部线程调仓颉"）
@C
public func cj_foreign_entry(x: Int32): Int64 {
    Int64(x) * 3
}

@C
public func cj_app_main(): Int64 {
    let v = unsafe { lwp_probe(6) }
    println("[engine] lwp_probe(6) = ${v}")
    // 让壳在新线程里回调 cj_foreign_entry
    let rc = unsafe { lwp_spawn_foreign() }
    println("[engine] spawn_foreign rc = ${rc}")
    Int64(v)
}

main(): Int64 { 0 }
