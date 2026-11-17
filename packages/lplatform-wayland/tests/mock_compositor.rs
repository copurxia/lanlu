//! 手写 wire-level 假合成器（M1W 的本地验证手段）。
//!
//! 本机没有 weston/sway，但 Wayland wire 协议很简单（实测见 `rawdump.rs`）：
//! `object_id(u32) | opcode(u16) | size(u16)` + 参数（小端）。
//! 用一个假合成器就能把「壳连上 → 枚举全局 → 建窗 → 收到 configure」跑通，且能进 CI。
//!
//! 两个测试：
//! 1. `client_enumerates_globals_from_mock`：只验证 registry/全局；
//! 2. `shell_creates_window_and_gets_configure`：用真正的 `Shell::connect` + `create_window`
//!    走完 xdg-shell 建窗流程，断言壳收到了合成器下发的 800×600。

use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex};

/// WAYLAND_DISPLAY 是**进程级**环境变量，两个测试并行会互相抢 —— 用锁串行化。
static ENV_LOCK: Mutex<()> = Mutex::new(());

// ── wire 层 ──────────────────────────────────────────────────────────────

/// 读若干字节，并把随消息一起到达的 fd（SCM_RIGHTS）取出来。
///
/// Wayland 用 ancillary data 传 fd（`wl_shm.create_pool` 等）。之前的 mock 用
/// `read_exact` 读，fd 会被内核丢弃 —— 于是"fd 传递"这条路径永远测不到。
/// std 的 `SocketAncillary` 还是 unstable，这里直接用 recvmsg。
fn read_exact_with_fds(s: &UnixStream, n: usize) -> std::io::Result<(Vec<u8>, Vec<i32>)> {
    use std::os::fd::AsRawFd;
    let mut buf = vec![0u8; n];
    let mut fds: Vec<i32> = Vec::new();
    let mut read = 0usize;
    while read < n {
        let mut iov = libc::iovec {
            iov_base: buf[read..].as_mut_ptr() as *mut libc::c_void,
            iov_len: n - read,
        };
        let mut cmsg_buf = [0u8; 256];
        let mut msg: libc::msghdr = unsafe { std::mem::zeroed() };
        msg.msg_iov = &mut iov;
        msg.msg_iovlen = 1;
        msg.msg_control = cmsg_buf.as_mut_ptr() as *mut libc::c_void;
        msg.msg_controllen = cmsg_buf.len() as _;
        let got = unsafe { libc::recvmsg(s.as_raw_fd(), &mut msg, 0) };
        if got < 0 {
            return Err(std::io::Error::last_os_error());
        }
        if got == 0 {
            return Err(std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "eof"));
        }
        read += got as usize;
        // 解析 cmsg 里的 SCM_RIGHTS
        unsafe {
            let mut cmsg = libc::CMSG_FIRSTHDR(&msg);
            while !cmsg.is_null() {
                let h = &*cmsg;
                if h.cmsg_level == libc::SOL_SOCKET && h.cmsg_type == libc::SCM_RIGHTS {
                    let data = libc::CMSG_DATA(cmsg);
                    let count = (h.cmsg_len - libc::CMSG_LEN(0) as usize) / std::mem::size_of::<i32>();
                    for i in 0..count {
                        let fd = *(data as *const i32).add(i);
                        fds.push(fd);
                    }
                }
                cmsg = libc::CMSG_NXTHDR(&msg, cmsg);
            }
        }
    }
    Ok((buf, fds))
}

/// 与 `read_msg` 相同，但同时返回这条消息携带的 fd（多数消息没有）。
fn read_msg_fds(s: &UnixStream) -> Option<(u32, u16, Vec<u8>, Vec<i32>)> {
    let (hdr, fds1) = read_exact_with_fds(s, 8).ok()?;
    let object = u32::from_le_bytes(hdr[0..4].try_into().unwrap());
    let opcode = u16::from_le_bytes(hdr[4..6].try_into().unwrap());
    let size = u16::from_le_bytes(hdr[6..8].try_into().unwrap()) as usize;
    if size < 8 {
        return None;
    }
    let mut fds = fds1;
    let (args, mut more) = read_exact_with_fds(s, size - 8).ok()?;
    fds.append(&mut more);
    Some((object, opcode, args, fds))
}

fn read_msg(s: &mut impl Read) -> Option<(u32, u16, Vec<u8>)> {
    let mut hdr = [0u8; 8];
    s.read_exact(&mut hdr).ok()?;
    let object = u32::from_le_bytes(hdr[0..4].try_into().unwrap());
    let opcode = u16::from_le_bytes(hdr[4..6].try_into().unwrap());
    let size = u16::from_le_bytes(hdr[6..8].try_into().unwrap()) as usize;
    if size < 8 {
        return None;
    }
    let mut args = vec![0u8; size - 8];
    if !args.is_empty() {
        s.read_exact(&mut args).ok()?;
    }
    Some((object, opcode, args))
}

fn write_msg(s: &mut impl Write, object: u32, opcode: u16, args: &[u8]) -> std::io::Result<()> {
    let size = (8 + args.len()) as u16;
    let mut buf = Vec::with_capacity(size as usize);
    buf.extend_from_slice(&object.to_le_bytes());
    buf.extend_from_slice(&opcode.to_le_bytes());
    buf.extend_from_slice(&size.to_le_bytes());
    buf.extend_from_slice(args);
    s.write_all(&buf)?;
    s.flush()
}

fn global(s: &mut impl Write, registry: u32, name: u32, iface: &str, version: u32) {
    let mut args = Vec::new();
    args.extend_from_slice(&name.to_le_bytes());
    let bytes = iface.as_bytes();
    args.extend_from_slice(&((bytes.len() as u32) + 1).to_le_bytes());
    args.extend_from_slice(bytes);
    args.push(0);
    while args.len() % 4 != 0 {
        args.push(0);
    }
    args.extend_from_slice(&version.to_le_bytes());
    let _ = write_msg(s, registry, 0, &args);
}

fn u32at(args: &[u8], off: usize) -> u32 {
    u32::from_le_bytes(args[off..off + 4].try_into().unwrap())
}

/// 起一个监听 socket，返回 (名字, listener)。名字给 WAYLAND_DISPLAY 用。
fn listen(tag: &str) -> (String, UnixListener) {
    let dir = std::path::PathBuf::from(
        std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into()),
    );
    let path = dir.join(format!("lanlu-{tag}-{}.sock", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).expect("bind");
    let name = path.file_name().unwrap().to_string_lossy().into_owned();
    std::env::set_var("WAYLAND_DISPLAY", &name);
    (name, listener)
}

// ── 测试 1：registry/全局 ─────────────────────────────────────────────────

#[test]
fn client_enumerates_globals_from_mock() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("globals");
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object != 1 {
                continue;
            }
            match opcode {
                0 if args.len() >= 4 => {
                    let cb = u32at(&args, 0);
                    let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                }
                1 if args.len() >= 4 => {
                    registry = u32at(&args, 0);
                    global(&mut s, registry, 1, "wl_compositor", 4);
                    global(&mut s, registry, 2, "wl_shm", 1);
                    global(&mut s, registry, 3, "xdg_wm_base", 1);
                }
                _ => {}
            }
        }
    });

    let conn = wayland_client::Connection::connect_to_env().expect("连接假合成器失败");
    let names = {
        let (globals, queue) =
            wayland_client::globals::registry_queue_init::<CS>(&conn).expect("registry 初始化失败");
        let names: Vec<String> = globals
            .contents()
            .clone_list()
            .iter()
            .map(|g| g.interface.clone())
            .collect();
        drop(globals);
        drop(queue);
        names
    };
    drop(conn); // 关 socket，服务端才会退出
    assert!(names.iter().any(|n| n == "wl_compositor"), "实际: {names:?}");
    assert!(names.iter().any(|n| n == "wl_shm"), "实际: {names:?}");
    assert!(names.iter().any(|n| n == "xdg_wm_base"), "实际: {names:?}");
    server.join().ok();
}

// ── 测试 2：真壳建窗 + configure ──────────────────────────────────────────

#[test]
fn shell_creates_window_and_gets_configure() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("xdg");
    let acks = Arc::new(Mutex::new(Vec::<u32>::new()));
    let acks_srv = Arc::clone(&acks);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        // 实测 id 分配（tests/probe_ids.rs 的探针输出）：
        //   bind: compositor=4, shm=5, xdg_wm_base=6；sync callback=7
        //   create_surface(4,op0)->8；get_xdg_surface(6,op2)->9；get_toplevel(9,op1)->10
        //   set_title/set_app_id(10,op2/op3)；commit(8,op6)
        let mut registry = 0u32;
        let mut compositor = 0u32;
        let mut wm_base = 0u32;
        let mut surface = 0u32;
        let mut xdg_surface = 0u32;
        let mut toplevel = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            // wl_display：sync(0) / get_registry(1)
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                    }
                    _ => {}
                }
                continue;
            }
            // wl_registry.bind(name, iface, version, new_id)
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        match iface.as_str() {
                            "wl_compositor" => compositor = new_id,
                            "xdg_wm_base" => wm_base = new_id,
                            _ => {}
                        }
                    }
                }
                continue;
            }
            // wl_compositor.create_surface(new_id)
            if object == compositor && opcode == 0 && args.len() >= 4 {
                surface = u32at(&args, 0);
                continue;
            }
            // xdg_wm_base.get_xdg_surface(new_id, surface)
            if object == wm_base && opcode == 2 && args.len() >= 8 {
                xdg_surface = u32at(&args, 0);
                continue;
            }
            // xdg_surface.get_toplevel(new_id)
            if object == xdg_surface && opcode == 1 && args.len() >= 4 {
                toplevel = u32at(&args, 0);
                continue;
            }
            // xdg_surface.ack_configure(serial)
            if object == xdg_surface && opcode == 4 && args.len() >= 4 {
                acks_srv.lock().unwrap().push(u32at(&args, 0));
                continue;
            }
            // wl_surface.commit -> 下发 configure（先 xdg_surface，再 xdg_toplevel）
            if object == surface && opcode == 6 {
                let _ = write_msg(&mut s, xdg_surface, 0, &7u32.to_le_bytes());
                let mut cfg = Vec::new();
                cfg.extend_from_slice(&800u32.to_le_bytes());
                cfg.extend_from_slice(&600u32.to_le_bytes());
                cfg.extend_from_slice(&0u32.to_le_bytes());
                let _ = write_msg(&mut s, toplevel, 0, &cfg);
            }
        }
    });

    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    // 起一个自己的 LWP 通道，注入 State：输入事件会直接投到这里
    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-test-{}", std::process::id()), 64).expect("打开 LWP 通道失败");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("首轮 roundtrip");
    let qh = queue.handle();
    let (_w_surf, w_xdg, _w_tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.xdg_surface = Some(w_xdg);
    queue.roundtrip(&mut state).expect("建窗 roundtrip");

    assert_eq!(state.pending, Some((800, 600)), "壳应收到 configure 尺寸");

    // 输入转发（wl_seat/pointer/keyboard → lw_input.*）已在 shell.rs 接线，
    // 但把它并入本测试会让 roundtrip 挂起（mock 的下发时机未调好）——
    // 当前只断言建窗流程，输入留给下一轮的单测/集成测。
    // 再走一轮：把 ack_configure 刷出去（wayland-client 的写是懒的）
    queue.roundtrip(&mut state).ok();
    let _ = shell.connection.flush();
    drop(queue);
    drop(shell);
    server.join().ok();
    // 壳在收到 xdg_surface.configure 后会 ack（当前实现是壳自作主张 ack，见计划待办）
    let n = acks.lock().unwrap().len();
    assert_eq!(n, 1, "应回一次 ack_configure，实际 {n}");
}

// ── 客户端 dispatch 占位 ──────────────────────────────────────────────────

struct CS;
impl wayland_client::Dispatch<wayland_client::protocol::wl_registry::WlRegistry,
    wayland_client::globals::GlobalListContents> for CS {
    fn event(
        _: &mut Self,
        _: &wayland_client::protocol::wl_registry::WlRegistry,
        _: <wayland_client::protocol::wl_registry::WlRegistry as wayland_client::Proxy>::Event,
        _: &wayland_client::globals::GlobalListContents,
        _: &wayland_client::Connection,
        _: &wayland_client::QueueHandle<Self>,
    ) {
    }
}

/// 输入链路：`wl_seat.capabilities` → 指针对象 → `wl_pointer.motion`
/// → 壳投递 `lw_input.pointer_motion` 到 LWP 通道。
#[test]
fn seat_input_is_forwarded_to_lwp() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("seat");
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut seat = 0u32;
        let mut pointer = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                        global(&mut s, registry, 4, "wl_seat", 7);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        if iface == "wl_seat" {
                            seat = new_id;
                            // wl_seat.capabilities(pointer|keyboard) 是事件 0
                            let _ = write_msg(&mut s, seat, 0, &3u32.to_le_bytes());
                        }
                    }
                }
                continue;
            }
            // wl_seat.get_pointer(0) / get_keyboard(1)
            if object == seat && (opcode == 0 || opcode == 1) && args.len() >= 4 {
                if opcode == 0 {
                    pointer = u32at(&args, 0);
                    // wl_pointer.motion(time, surface_x, surface_y) 是事件 2 —— **带 time**，
                    // 漏了 time 会让客户端按 12 字节参数读取而错位（第 64 轮踩过）。
                    // wl_fixed 是 24.8 定点：12.5 -> 12.5*256 = 3200
                    // （最初直接塞 f32 位模式，客户端当成 wl_fixed 解析，坐标变成 427 万）
                    let mut ev = Vec::new();
                    ev.extend_from_slice(&1u32.to_le_bytes());          // time
                    ev.extend_from_slice(&3200i32.to_le_bytes());       // surface_x = 12.5
                    let sy = (34.5f64 * 256.0) as i32;                              // surface_y = 34.5
                    ev.extend_from_slice(&sy.to_le_bytes());
                    let _ = write_msg(&mut s, pointer, 2, &ev);
                }
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-seat-{}", std::process::id()), 64).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    // 录制开关与生产一致（§16.3）：有 LANLU_LWP_TRACE 就录，测试里写临时文件
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("roundtrip");
    // 再走一轮：让 get_pointer 发出去、motion 回来
    queue.roundtrip(&mut state).expect("输入 roundtrip");
    let _ = shell.connection.flush();

    let mut motions = 0;
    {
        let c = shared.lock().unwrap();
        while let Some(m) = c.recv(lanlu_platform_wayland::lwp::LWP_EVENT) {
            if m.iface == 2 && m.opcode == 1 {
                motions += 1;
                assert_eq!(m.body.len(), 12, "pointer_motion 应为 12 字节");
                let x = f32::from_le_bytes(m.body[4..8].try_into().unwrap());
                let y = f32::from_le_bytes(m.body[8..12].try_into().unwrap());
                assert!((x - 12.5).abs() < 1e-6, "x 应为 12.5，实际 {x}");
                assert!((y - 34.5).abs() < 1e-6, "y 应为 34.5，实际 {y}");
            }
        }
    }
    drop(queue);
    drop(shell);
    server.join().ok();
    assert!(motions >= 1, "应当至少收到一条 lw_input.pointer_motion，实际 {motions}");
}

/// 上屏路径：引擎给出共享内存 fd → 壳建 wl_shm 池/buffer → attach + damage + commit。
/// 断言的是**合成器视角的请求序列**（像素是否真的显示需要真实合成器）。
#[test]
fn surface_attach_creates_shm_buffer() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("shm");
    let seen = Arc::new(Mutex::new(Vec::<String>::new()));
    let seen_srv = Arc::clone(&seen);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut shm_id = 0u32;
        let mut surface = 0u32;
        let mut pool = 0u32;
        let mut buffer = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        match iface.as_str() {
                            "wl_shm" => shm_id = new_id,
                            "xdg_wm_base" => wm_base = new_id,
                            _ => {}
                        }
                    }
                }
                continue;
            }
            // wl_shm.create_pool(new_id, size) —— fd 通过 SCM_RIGHTS 传，这里只能记请求
            if object == shm_id && opcode == 0 && args.len() >= 8 {
                pool = u32at(&args, 0);
                seen_srv.lock().unwrap().push("create_pool".into());
                continue;
            }
            // wl_shm_pool.create_buffer(new_id, ...)
            if object == pool && opcode == 0 && args.len() >= 4 {
                buffer = u32at(&args, 0);
                seen_srv.lock().unwrap().push("create_buffer".into());
                continue;
            }
            // wl_surface.attach(buffer) / damage / commit
            if object == surface {
                match opcode {
                    1 => seen_srv.lock().unwrap().push("attach".into()),
                    2 => seen_srv.lock().unwrap().push("damage".into()),
                    6 => {
                        seen_srv.lock().unwrap().push("commit".into());
                        // 回 wl_buffer.release，让壳可复用
                        if buffer != 0 {
                            let _ = write_msg(&mut s, buffer, 0, &[]);
                        }
                    }
                    _ => {}
                }
                continue;
            }
            // wl_compositor.create_surface
            if opcode == 0 && args.len() >= 4 && object != wm_base && object != shm_id {
                surface = u32at(&args, 0);
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-shm-{}", std::process::id()), 64).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("roundtrip");
    let qh = queue.handle();
    let (wl_surf, xdg_s, _tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.surface = Some(wl_surf.clone());
    state.xdg_surface = Some(xdg_s);
    queue.roundtrip(&mut state).expect("建窗 roundtrip");

    // 造一块共享内存（近似「引擎交来的 fd」）
    let mut path = std::env::temp_dir();
    path.push(format!("lanlu-shm-{}.bin", std::process::id()));
    let file = std::fs::File::create(&path).expect("建临时文件");
    file.set_len(64 * 48 * 4).expect("设置大小");
    let fd = {
        use std::os::fd::AsRawFd;
        file.as_raw_fd()
    };
    let reused1 = state.attach_shm(&shell, &qh, fd, 64, 48).expect("attach_shm 失败");
    queue.roundtrip(&mut state).expect("attach roundtrip");
    assert!(!reused1, "首帧不应复用");

    // 第二帧同一个 fd/尺寸：应当复用（不再 create_pool/create_buffer）
    let before = seen.lock().unwrap().len();
    let reused2 = state.attach_shm(&shell, &qh, fd, 64, 48).expect("第二次 attach 失败");
    queue.roundtrip(&mut state).expect("第二次 roundtrip");
    assert!(reused2, "同 fd 同尺寸应当复用缓冲");
    let after = seen.lock().unwrap().len();
    let pools = seen.lock().unwrap().iter().filter(|x| *x == "create_pool").count();
    assert_eq!(pools, 1, "复用后不应再建 pool，实际 {pools} 次");
    assert!(after > before, "第二次仍应有 attach/damage/commit 请求");

    let seq = seen.lock().unwrap().clone();
    assert!(seq.iter().any(|x| x == "create_pool"), "应有 create_pool，实际 {seq:?}");
    assert!(seq.iter().any(|x| x == "create_buffer"), "应有 create_buffer，实际 {seq:?}");
    assert!(seq.iter().any(|x| x == "attach"), "应有 attach，实际 {seq:?}");
    assert!(seq.iter().any(|x| x == "damage"), "应有 damage，实际 {seq:?}");
    assert!(seq.iter().any(|x| x == "commit"), "应有 commit，实际 {seq:?}");

    let _ = std::fs::remove_file(&path);
    drop(queue);
    drop(shell);
    server.join().ok();
}

/// 系统事实：壳把 system.info 发进通道，字段可被解析（时区/语言/字体目录/home/api）。
#[test]
fn shell_announces_system_info() {
    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-sysinfo-{}", std::process::id()), 32).expect("通道");
    ch.enable_checker(false);
    lanlu_platform_wayland::shell::announce_system_info(&ch);
    let m = ch.recv(lanlu_platform_wayland::lwp::LWP_REQUEST).expect("应当收到 system.info");
    assert_eq!(m.iface, 12, "iface 应为 lw_system");
    assert_eq!(m.opcode, 0, "opcode 应为 system.info");
    assert!(m.body.len() >= 24, "头部 24 字节");
    // 第一个字符串（时区）的 off/len
    let off = u16::from_le_bytes([m.body[4], m.body[5]]) as usize;
    let len = u16::from_le_bytes([m.body[6], m.body[7]]) as usize;
    assert!(off + len <= m.body.len(), "字符串应落在 body 内");
    let tz = String::from_utf8_lossy(&m.body[off..off + len]).into_owned();
    assert!(!tz.is_empty(), "时区不应为空，实际 {tz:?}");
}

/// 窗口状态：`set_maximized/unset_maximized/set_fullscreen/unset_fullscreen/destroy`
/// 必须打在 xdg_toplevel 对象上（opcode 11/12/13/14/0，见 xdg-shell 请求顺序）。
#[test]
fn window_state_maps_to_toplevel_requests() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("ws");

    let seen = Arc::new(Mutex::new(Vec::<(u32, u16)>::new()));
    let seen_srv = Arc::clone(&seen);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut xdg = 0u32;
        let mut toplevel = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        if iface == "xdg_wm_base" {
                            wm_base = u32at(&args, args.len() - 4);
                        }
                    }
                }
                continue;
            }
            if object == wm_base && opcode == 2 && args.len() >= 8 {
                xdg = u32at(&args, 0);
                continue;
            }
            if object == xdg && opcode == 1 && args.len() >= 4 {
                toplevel = u32at(&args, 0);
                continue;
            }
            if object == toplevel {
                seen_srv.lock().unwrap().push((object, opcode));
                continue;
            }
        }
    });

    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State::default();
    queue.roundtrip(&mut state).expect("roundtrip");
    let qh = queue.handle();
    let (_surf, xdg_s, tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.xdg_surface = Some(xdg_s);
    state.toplevel = Some(tl.clone());

    tl.set_maximized();
    tl.unset_maximized();
    tl.set_fullscreen(None);
    tl.unset_fullscreen();
    queue.roundtrip(&mut state).expect("state roundtrip");

    let ops: Vec<u16> = seen.lock().unwrap().iter().map(|(_, op)| *op).collect();
    // xdg-shell 的请求编号（按 XML 声明顺序）：
    // destroy=0 set_parent=1 set_title=2 set_app_id=3 show_window_menu=4 move=5 resize=6
    // set_max_size=7 set_min_size=8 set_maximized=9 unset_maximized=10
    // set_fullscreen=11 unset_fullscreen=12 set_minimized=13
    assert!(ops.contains(&9), "应有 set_maximized(9)，实际 {ops:?}");
    assert!(ops.contains(&10), "应有 unset_maximized(10)，实际 {ops:?}");
    assert!(ops.contains(&11), "应有 set_fullscreen(11)，实际 {ops:?}");
    assert!(ops.contains(&12), "应有 unset_fullscreen(12)，实际 {ops:?}");

    drop(queue);
    drop(shell);
    server.join().ok();
}

/// configure -> `lw_surface.changed`：合成器下发尺寸后，壳要通知引擎并 ack。
#[test]
fn configure_emits_surface_changed() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("cfg");

    let acks = Arc::new(Mutex::new(Vec::<u32>::new()));
    let acks_srv = Arc::clone(&acks);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut compositor = 0u32;
        let mut surface = 0u32;
        let mut xdg = 0u32;
        let mut toplevel = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        match iface.as_str() {
                            "wl_compositor" => compositor = new_id,
                            "xdg_wm_base" => wm_base = new_id,
                            _ => {}
                        }
                    }
                }
                continue;
            }
            if object == compositor && opcode == 0 && args.len() >= 4 {
                surface = u32at(&args, 0);
                continue;
            }
            if object == wm_base && opcode == 2 && args.len() >= 8 {
                xdg = u32at(&args, 0);
                continue;
            }
            if object == xdg && opcode == 1 && args.len() >= 4 {
                toplevel = u32at(&args, 0);
                continue;
            }
            if object == xdg && opcode == 4 && args.len() >= 4 {
                acks_srv.lock().unwrap().push(u32at(&args, 0));
                continue;
            }
            if object == surface && opcode == 6 {
                // 先发 toplevel 尺寸，再发 xdg_surface.configure（顺序反了也应能处理）
                let mut cfg = Vec::new();
                cfg.extend_from_slice(&1024u32.to_le_bytes());
                cfg.extend_from_slice(&768u32.to_le_bytes());
                cfg.extend_from_slice(&0u32.to_le_bytes());
                let _ = write_msg(&mut s, toplevel, 0, &cfg);
                let _ = write_msg(&mut s, xdg, 0, &5u32.to_le_bytes());
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-cfg-{}", std::process::id()), 64).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("roundtrip");
    let qh = queue.handle();
    let (wl_surf, xdg_surf, tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.surface = Some(wl_surf);
    state.xdg_surface = Some(xdg_surf);
    state.toplevel = Some(tl);
    queue.roundtrip(&mut state).expect("configure roundtrip");
    // 再走一轮：ack_configure 是在收到事件的回调里排队的，要再 flush 一次才出去
    queue.roundtrip(&mut state).expect("ack roundtrip");

    // 壳应已发出 surface.changed(1024x768)
    let mut changed: Option<(u32, u32)> = None;
    {
        let c = shared.lock().unwrap();
        while let Some(m) = c.recv(lanlu_platform_wayland::lwp::LWP_REQUEST) {
            if m.iface == 5 && m.opcode == 1 && m.body.len() >= 12 {
                changed = Some((
                    u32::from_le_bytes(m.body[4..8].try_into().unwrap()),
                    u32::from_le_bytes(m.body[8..12].try_into().unwrap()),
                ));
            }
        }
    }
    assert_eq!(changed, Some((1024, 768)), "应发出 surface.changed(1024,768)");
    assert_eq!(acks.lock().unwrap().as_slice(), &[5u32], "应 ack 一次 configure");

    drop(queue);
    drop(shell);
    server.join().ok();
}

/// DPI：合成器报 scale=2 时，壳要在 `set_buffer_scale(2)` 上体现（wl_surface 请求 8）。
#[test]
fn output_scale_sets_buffer_scale() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("scale");
    let scales = Arc::new(Mutex::new(Vec::<u32>::new()));
    let scales_srv = Arc::clone(&scales);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut surface = 0u32;
        let mut xdg = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                        global(&mut s, registry, 4, "wl_output", 4);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        if iface == "xdg_wm_base" {
                            wm_base = new_id;
                        } else if iface == "wl_output" {
                            // wl_output 事件顺序：geometry(0) mode(1) done(2) scale(3) name(4)
                            // —— scale 是 **3** 不是 4；发错编号会让客户端把 4 当 name(字符串) 解析而错位。
                            let _ = write_msg(&mut s, new_id, 3, &2i32.to_le_bytes());
                        }
                    }
                }
                continue;
            }
            if object == wm_base && opcode == 2 && args.len() >= 8 {
                xdg = u32at(&args, 0);
                continue;
            }
            if object == xdg && opcode == 1 && args.len() >= 4 {
                continue;
            }
            if opcode == 8 && args.len() >= 4 {
                // wl_surface.set_buffer_scale
                scales_srv.lock().unwrap().push(u32at(&args, 0));
                continue;
            }
            if opcode == 0 && args.len() >= 4 && object != wm_base && object != registry {
                surface = u32at(&args, 0);
                let _ = surface;
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-scale-{}", std::process::id()), 32).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("roundtrip");
    assert_eq!(state.output_scale, 2, "应收到 wl_output.scale=2");

    let qh = queue.handle();
    let (wl_surf, xdg_s, _tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.surface = Some(wl_surf);
    state.xdg_surface = Some(xdg_s);
    // 触发 flush：制造一次 configure
    state.pending = Some((640, 480));
    state.pending_configure_serial = Some(1);
    state.flush_configure();
    queue.roundtrip(&mut state).expect("scale roundtrip");

    assert_eq!(scales.lock().unwrap().as_slice(), &[2u32], "应发 set_buffer_scale(2)");
    drop(queue);
    drop(shell);
    server.join().ok();
}

/// 剪贴板读回：管道里有数据时，`poll_clipboard_read` 应发出 `clipboard.text`。
#[test]
fn clipboard_read_emits_text() {
    use std::io::Write;
    use std::os::unix::net::UnixStream;

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-clip-{}", std::process::id()), 32).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };

    let (ours, mut theirs) = UnixStream::pair().expect("pair");
    ours.set_nonblocking(true).expect("nonblock");
    theirs.write_all("你好，剪贴板".as_bytes()).expect("write");
    drop(theirs);   // EOF：读完就该结束

    state.pending_read = Some((ours, "text/plain;charset=utf-8".to_string()));
    state.pending_get_serial = Some(9);

    assert!(state.poll_clipboard_read(), "应当完成一次读回");

    let c = shared.lock().unwrap();
    let m = c.recv(lanlu_platform_wayland::lwp::LWP_REQUEST).expect("应当收到 clipboard.text");
    assert_eq!(m.iface, lanlu_platform_wayland::protocol::iface::CLIPBOARD, "iface 应为 lw_clipboard");
    assert_eq!(m.opcode, 0, "opcode 应为 clipboard.text");
    let serial = u32::from_le_bytes(m.body[4..8].try_into().unwrap());
    assert_eq!(serial, 9, "serial 应原样带回");
    // mime 头在 8..12，text 头在 12..16
    let mime_off = u16::from_le_bytes([m.body[8], m.body[9]]) as usize;
    let mime_len = u16::from_le_bytes([m.body[10], m.body[11]]) as usize;
    let text_off = u16::from_le_bytes([m.body[12], m.body[13]]) as usize;
    let text_len = u16::from_le_bytes([m.body[14], m.body[15]]) as usize;
    assert_eq!(String::from_utf8_lossy(&m.body[mime_off..mime_off + mime_len]),
        "text/plain;charset=utf-8");
    assert_eq!(String::from_utf8_lossy(&m.body[text_off..text_off + text_len]),
        "你好，剪贴板");
}

/// mime 协商：从 offer 的 mime 列表里挑 UTF-8 优先的那个。
#[test]
fn mime_preference_order() {
    let mut st = lanlu_platform_wayland::shell::State::default();

    // 只有 text/plain：就选它
    st.offer_mimes = vec!["text/plain".to_string()];
    assert_eq!(st.pick_mime(), Some("text/plain"));

    // 有 utf8 变体：优先 charset=utf-8（大小写不敏感）
    st.offer_mimes = vec![
        "STRING".to_string(),
        "text/plain".to_string(),
        "text/plain;charset=UTF-8".to_string(),
    ];
    assert_eq!(st.pick_mime(), Some("text/plain;charset=UTF-8"));

    // 一个都不认识：返回 None（调用方退回默认 utf8）
    st.offer_mimes = vec!["image/png".to_string()];
    assert_eq!(st.pick_mime(), None);

    // 空列表
    st.offer_mimes.clear();
    assert_eq!(st.pick_mime(), None);
}

/// 交互式移动/缩放：引擎发 begin_move/begin_resize 后，壳应发 xdg_toplevel.move(5)/resize(6)。
#[test]
fn begin_move_and_resize_map_to_xdg_requests() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("drag");
    let seen = Arc::new(Mutex::new(Vec::<(u32, u16)>::new()));
    let seen_srv = Arc::clone(&seen);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut compositor = 0u32;
        let mut xdg = 0u32;
        let mut toplevel = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                        global(&mut s, registry, 4, "wl_seat", 7);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        match iface.as_str() {
                            "wl_compositor" => compositor = new_id,
                            "xdg_wm_base" => wm_base = new_id,
                            _ => {}
                        }
                    }
                }
                continue;
            }
            if object == compositor && opcode == 0 && args.len() >= 4 {
                continue;
            }
            if object == wm_base && opcode == 2 && args.len() >= 8 {
                xdg = u32at(&args, 0);
                continue;
            }
            if object == xdg && opcode == 1 && args.len() >= 4 {
                toplevel = u32at(&args, 0);
                continue;
            }
            if object == toplevel {
                seen_srv.lock().unwrap().push((object, opcode));
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-drag-{}", std::process::id()), 32).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("roundtrip");
    let qh = queue.handle();
    let (_surf, xdg_s, tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.xdg_surface = Some(xdg_s);
    state.toplevel = Some(tl.clone());
    state.last_input_serial = 42;

    // 直接调壳内部逻辑（不经过 LWP 通道，避免依赖 seat 的时序）
    tl._move(shell.seat.as_ref().expect("seat"), 42);
    tl.resize(shell.seat.as_ref().expect("seat"), 42,
        lanlu_platform_wayland::shell::test_edges(8));
    queue.roundtrip(&mut state).expect("drag roundtrip");

    let ops: Vec<u16> = seen.lock().unwrap().iter().map(|(_, op)| *op).collect();
    assert!(ops.contains(&5), "应有 xdg_toplevel.move(5)，实际 {ops:?}");
    assert!(ops.contains(&6), "应有 xdg_toplevel.resize(6)，实际 {ops:?}");

    drop(queue);
    drop(shell);
    server.join().ok();
}

/// 多屏 DPI：两个 output（scale 1 和 2），表面 enter 第二个后应按 2 设 buffer scale。
#[test]
fn multi_output_switch_scale() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("multiout");
    let scales = Arc::new(Mutex::new(Vec::<u32>::new()));
    let scales_srv = Arc::clone(&scales);
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut output2 = 0u32;
        let mut surface = 0u32;
        let mut xdg = 0u32;
        while let Some((object, opcode, args)) = read_msg(&mut s) {
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let _ = write_msg(&mut s, cb, 0, &0u32.to_le_bytes());
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut s, registry, 1, "wl_compositor", 4);
                        global(&mut s, registry, 2, "wl_shm", 1);
                        global(&mut s, registry, 3, "xdg_wm_base", 1);
                        global(&mut s, registry, 4, "wl_output", 4);   // 第一个：scale 1
                        global(&mut s, registry, 5, "wl_output", 4);   // 第二个：scale 2
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        match (iface.as_str(), u32at(&args, 0)) {
                            ("xdg_wm_base", _) => wm_base = new_id,
                            ("wl_output", 4) => {
                                let _ = write_msg(&mut s, new_id, 3, &1i32.to_le_bytes());
                            }
                            ("wl_output", 5) => {
                                output2 = new_id;
                                let _ = write_msg(&mut s, new_id, 3, &2i32.to_le_bytes());
                            }
                            _ => {}
                        }
                    }
                }
                continue;
            }
            if object == wm_base && opcode == 2 && args.len() >= 8 {
                xdg = u32at(&args, 0);
                continue;
            }
            if object == xdg && opcode == 1 && args.len() >= 4 {
                continue;
            }
            if opcode == 8 && args.len() >= 4 {
                scales_srv.lock().unwrap().push(u32at(&args, 0));
                continue;
            }
            if opcode == 0 && args.len() >= 4 && object != wm_base && object != registry {
                surface = u32at(&args, 0);
                // 表面进入第二个显示器（enter 是事件 0）
                let _ = write_msg(&mut s, surface, 0, &output2.to_le_bytes());
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-multi-{}", std::process::id()), 32).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    queue.roundtrip(&mut state).expect("roundtrip");
    assert_eq!(shell.outputs.len(), 2, "应绑定两个 output");
    let qh = queue.handle();
    let (wl_surf, xdg_s, _tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    state.surface = Some(wl_surf);
    state.xdg_surface = Some(xdg_s);
    queue.roundtrip(&mut state).expect("enter roundtrip");
    assert_eq!(state.output_scale, 2, "表面在第二个屏上，scale 应为 2");

    // 触发一次 flush，把 buffer scale 发出去
    state.pending = Some((640, 480));
    state.pending_configure_serial = Some(1);
    state.flush_configure();
    queue.roundtrip(&mut state).expect("scale roundtrip");
    assert_eq!(scales.lock().unwrap().last().copied(), Some(2u32),
        "应发 set_buffer_scale(2)");

    drop(queue);
    drop(shell);
    server.join().ok();
}

/// 拖放的 uri 解码：file:// → 本地路径，百分号转义要还原。
#[test]
fn drag_uri_decoding() {
    use lanlu_platform_wayland::shell::test_uri_to_path;
    assert_eq!(test_uri_to_path("file:///home/u/a.txt"), "/home/u/a.txt");
    assert_eq!(test_uri_to_path("file:///tmp/%E4%B8%AD%E6%96%87.txt"), "/tmp/中文.txt");
    assert_eq!(test_uri_to_path("https://x/y"), "https://x/y");
    assert_eq!(test_uri_to_path("/already/path"), "/already/path");
}

/// fd 传递（SCM_RIGHTS）：客户端 `wl_shm.create_pool` 会附带一个 fd，
/// 假合成器要真的收到它 —— 否则"共享内存上屏"这条路径在测试里是盲区。
#[test]
fn shm_pool_passes_fd_over_scm_rights() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("fdpass");
    let got = Arc::new(Mutex::new(Vec::<usize>::new()));
    let got_srv = Arc::clone(&got);
    let server = std::thread::spawn(move || {
        let (s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut wm_base = 0u32;
        let mut compositor = 0u32;
        let mut shm = 0u32;
        while let Some((object, opcode, args, fds)) = read_msg_fds(&s) {
            if !fds.is_empty() {
                got_srv.lock().unwrap().push(fds.len());
            }
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let mut w = Vec::new();
                        w.extend_from_slice(&cb.to_le_bytes());
                        w.extend_from_slice(&0u16.to_le_bytes());
                        w.extend_from_slice(&12u16.to_le_bytes());
                        w.extend_from_slice(&0u32.to_le_bytes());
                        let _ = (&s).write_all(&w);
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut (&s), registry, 1, "wl_compositor", 4);
                        global(&mut (&s), registry, 2, "wl_shm", 1);
                        global(&mut (&s), registry, 3, "xdg_wm_base", 1);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        match iface.as_str() {
                            "wl_compositor" => compositor = new_id,
                            "wl_shm" => shm = new_id,
                            "xdg_wm_base" => wm_base = new_id,
                            _ => {}
                        }
                    }
                }
                continue;
            }
            let _ = (compositor, wm_base, shm);
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-fd-{}", std::process::id()), 16).expect("通道");
    ch.enable_checker(false);
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State::default();
    queue.roundtrip(&mut state).expect("roundtrip");
    let qh = queue.handle();
    // 建一块共享内存并让壳把它挂上去（内部会 create_pool 带 fd）
    let mut path = std::env::temp_dir();
    path.push(format!("lanlu-fd-{}.bin", std::process::id()));
    let file = std::fs::File::create(&path).expect("temp");
    file.set_len(64 * 48 * 4).expect("len");
    let fd = {
        use std::os::fd::AsRawFd;
        file.as_raw_fd()
    };
    let (surf, _xdg, _tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
    let _ = shell.attach_shm(&qh, &surf, fd, 64, 48).expect("attach_shm");
    queue.roundtrip(&mut state).expect("attach roundtrip");

    assert!(!got.lock().unwrap().is_empty(), "create_pool 应当带一个 fd（SCM_RIGHTS）");
    let _ = std::fs::remove_file(&path);
    drop(queue);
    drop(shell);
    server.join().ok();
}

/// 剪贴板 receive 的真实 fd 路径：壳向 offer 要数据（带 fd），对面写进来，壳读回并发 clipboard.text。
#[test]
fn clipboard_receive_uses_fd_and_returns_text() {
    let _serial = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_name, listener) = listen("clipfd");
    let server = std::thread::spawn(move || {
        let (s, _) = listener.accept().expect("accept");
        let mut registry = 0u32;
        let mut manager = 0u32;
        let mut offer = 0u32;
        while let Some((object, opcode, args, fds)) = read_msg_fds(&s) {
            // 收到带 fd 的请求 = wl_data_offer.receive：往 fd 里写内容再关掉
            if !fds.is_empty() {
                let text = b"clipboard-from-other-app";
                unsafe {
                    libc::write(fds[0], text.as_ptr() as *const libc::c_void, text.len());
                    libc::close(fds[0]);
                }
                continue;
            }
            if object == 1 {
                match opcode {
                    0 if args.len() >= 4 => {
                        let cb = u32at(&args, 0);
                        let mut w = Vec::new();
                        w.extend_from_slice(&cb.to_le_bytes());
                        w.extend_from_slice(&0u16.to_le_bytes());
                        w.extend_from_slice(&12u16.to_le_bytes());
                        w.extend_from_slice(&0u32.to_le_bytes());
                        let _ = (&s).write_all(&w);
                    }
                    1 if args.len() >= 4 => {
                        registry = u32at(&args, 0);
                        global(&mut (&s), registry, 1, "wl_compositor", 4);
                        global(&mut (&s), registry, 2, "wl_shm", 1);
                        global(&mut (&s), registry, 3, "xdg_wm_base", 1);
                        global(&mut (&s), registry, 4, "wl_seat", 7);
                        global(&mut (&s), registry, 5, "wl_data_device_manager", 3);
                    }
                    _ => {}
                }
                continue;
            }
            if object == registry {
                if args.len() >= 12 {
                    let slen = u32at(&args, 4) as usize;
                    if slen > 0 && 8 + slen <= args.len() {
                        let iface = String::from_utf8_lossy(&args[8..8 + slen - 1]).into_owned();
                        let new_id = u32at(&args, args.len() - 4);
                        if iface == "wl_data_device_manager" {
                            manager = new_id;
                        }
                    }
                }
                continue;
            }
            // wl_data_device_manager.get_data_device(new_id)：拿到 id 后立刻投递选区
            if object == manager && opcode == 1 && args.len() >= 4 {
                let dd = u32at(&args, 0);
                // 服务端创建的对象必须用 **server id 空间**（>= 0xFF00_0000）。
                // rs 后端的 ObjectMap 把 id 分成 client/server 两段；用客户端段的小 id
                // 会被判 "invalid id"（第 99 轮实测）。
                let _ = dd;
                offer = 0xFF00_0000;   // 服务端 id 空间从 SERVER_ID_LIMIT 起，且必须连续
                // data_offer(new_id) 是事件 0
                let _ = write_msg(&mut (&s), dd, 0, &offer.to_le_bytes());
                // wl_data_offer.offer(mime) 是事件 0
                let mime = b"text/plain;charset=utf-8";
                let mut ev = Vec::new();
                ev.extend_from_slice(&((mime.len() as u32) + 1).to_le_bytes());
                ev.extend_from_slice(mime);
                ev.push(0);
                while ev.len() % 4 != 0 { ev.push(0); }
                let _ = write_msg(&mut (&s), offer, 0, &ev);
                // wl_data_device.selection(offer) 是事件 5
                let _ = write_msg(&mut (&s), dd, 5, &offer.to_le_bytes());
                continue;
            }
        }
    });

    let ch = lanlu_platform_wayland::lwp::Channel::open(
        &format!("wayland-clipfd-{}", std::process::id()), 32).expect("通道");
    ch.enable_checker(false);
    let shared = Arc::new(Mutex::new(ch));
    let (shell, mut queue) =
        lanlu_platform_wayland::shell::Shell::connect().expect("连假合成器失败");
    let mut state = lanlu_platform_wayland::shell::State {
        channel: Some(Arc::clone(&shared)),
        ..Default::default()
    };
    // 与 run() 一致：先建 data device（生产路径里在 run() 里做，测试要自己调）
    {
        let qh = queue.handle();
        if let (Some(dm), Some(seat)) = (&shell.data_manager, &shell.seat) {
            state.data_device = Some(dm.get_data_device(seat, &qh, ()));
        }
    }
    queue.roundtrip(&mut state).expect("roundtrip");
    assert!(state.selection_offer.is_some(), "应收到选区 offer");
    assert!(!state.offer_mimes.is_empty(), "offer 应带 mime");

    // 引擎侧发起 clipboard.get：壳向 offer 要数据
    state.pending_get_serial = Some(77);
    state.start_clipboard_read("text/plain;charset=utf-8").expect("发起读取");
    queue.roundtrip(&mut state).expect("receive roundtrip");
    // 读回（假合成器已把内容写进管道）
    for _ in 0..20 {
        if state.poll_clipboard_read() { break; }
        std::thread::sleep(std::time::Duration::from_millis(5));
        queue.roundtrip(&mut state).ok();
    }

    let c = shared.lock().unwrap();
    let m = c.recv(lanlu_platform_wayland::lwp::LWP_REQUEST).expect("应收到 clipboard.text");
    assert_eq!(m.iface, lanlu_platform_wayland::protocol::iface::CLIPBOARD, "iface = lw_clipboard");
    assert_eq!(m.opcode, 0, "opcode = clipboard.text");
    assert_eq!(u32::from_le_bytes(m.body[4..8].try_into().unwrap()), 77, "serial");
    let to = u16::from_le_bytes([m.body[12], m.body[13]]) as usize;
    let tl = u16::from_le_bytes([m.body[14], m.body[15]]) as usize;
    let text = String::from_utf8_lossy(&m.body[to..to + tl]).into_owned();
    assert_eq!(text, "clipboard-from-other-app", "读回的内容应等于对面写入的");

    drop(c);
    drop(queue);
    drop(shell);
    server.join().ok();
}
