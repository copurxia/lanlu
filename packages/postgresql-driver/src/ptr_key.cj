package postgresql_driver

// 指针身份键：CPointer 无 ==/hash，经 bridge 取地址整数值做 HashMap 键。
@FastNative
foreign func llpg_ptr_key(p: CPointer<Unit>): UInt64

/** 连接指针 -> 稳定 UInt64 键（0 表示空指针）。 */
func connPtrKey(c: CPointer<Unit>): UInt64 {
    if (c.isNull()) {
        return 0u64
    }
    unsafe { llpg_ptr_key(c) }
}
