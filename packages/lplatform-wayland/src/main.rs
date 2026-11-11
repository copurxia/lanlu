//! Lanlu Wayland 壳（M1W）。
//!
//! 计划：docs/lwindow-platform-separation-plan.md §4.4、§9.3。
//! 分层：`protocol`（LWP 编解码，纯逻辑、可测）→ `lwp`（通道 FFI）→ wayland 事件循环。

use lanlu_platform_wayland::{lwp, protocol, shell};

fn main() {
    // 通道是否可用决定后面走协议还是直接退出（M1W 阶段先只报状态）。
    let channel = lwp::Channel::open("lanlu", 256);
    match channel {
        Ok(ch) => {
            ch.enable_checker(false);
            let _ = ch.send(lwp::LWP_EVENT, protocol::iface::CORE, protocol::op::CORE_HELLO,
                0, protocol::hello("wayland", "linux", 0, 0).as_slice());
            println!("lanlu (wayland shell) — hello 已发出，统计: {}", ch.stats());
            // M1W：连接合成器并进事件循环；本机没有合成器时会打印原因后退出。
            match shell::run(ch) {
                Ok(()) => {}
                Err(e) => {
                    println!("[wayland] 无法进入事件循环: {e}");
                    println!("提示：需要 WAYLAND_DISPLAY 指向一个运行中的合成器（weston / sway / 桌面会话）");
                }
            }
        }
        Err(e) => {
            println!("lanlu (wayland shell) — LWP 通道不可用: {e}");
            println!("提示：先构建 liblwp_native.so（bash packages/lwp/native/build.sh）并设置 LD_LIBRARY_PATH");
        }
    }
}
