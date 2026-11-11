//! wire 格式对照测试：把 `wayland-client` 实际发出的字节记录下来并断言其结构。
//!
//! 价值：手写 mock 合成器（M1W 的本地验证手段）依赖对 wire 格式的正确理解；
//! 这个测试把「客户端第一件事是 `wl_display.get_registry`，紧接着 `sync`」固化成断言，
//! 以后改 mock 时不会靠猜。
use std::io::Read;
use std::os::unix::net::UnixListener;

#[test]
fn dump_client_bytes() {
    let dir = std::path::PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or("/tmp".into()));
    let path = dir.join(format!("lanlu-dump-{}.sock", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).unwrap();
    let name = path.file_name().unwrap().to_string_lossy().into_owned();
    std::env::set_var("WAYLAND_DISPLAY", &name);

    let captured = std::sync::Arc::new(std::sync::Mutex::new(Vec::<u8>::new()));
    let captured_srv = std::sync::Arc::clone(&captured);
    let h = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let mut buf = [0u8; 256];
        let mut all = Vec::new();
        s.set_read_timeout(Some(std::time::Duration::from_millis(800))).ok();
        while let Ok(n) = s.read(&mut buf) {
            if n == 0 { break; }
            all.extend_from_slice(&buf[..n]);
        }
        eprintln!("[dump] {} bytes", all.len());
        captured_srv.lock().unwrap().extend_from_slice(&all);
    });

    let conn = wayland_client::Connection::connect_to_env().expect("connect");
    let _ = wayland_client::globals::registry_queue_init::<CS>(&conn);
    h.join().ok();

    let bytes = captured.lock().unwrap().clone();
    assert!(bytes.len() >= 24, "至少应看到 get_registry + sync 两条消息");
    // 第 1 条：object=1(wl_display), opcode=1(get_registry), len=12
    assert_eq!(u32::from_le_bytes(bytes[0..4].try_into().unwrap()), 1);
    // 头部顺序是 object_id(u32) + opcode(u16) + size(u16) —— **opcode 在前**（第 60 轮猜反了）
    let w = u32::from_le_bytes(bytes[4..8].try_into().unwrap());
    assert_eq!((w & 0xffff) as u16, 1, "opcode 应为 get_registry(1)");
    assert_eq!((w >> 16) as u16, 12, "get_registry 长度应为 12");
    assert_eq!(u32::from_le_bytes(bytes[8..12].try_into().unwrap()), 2, "new_id 应为 2");
    // 第 2 条：object=1, opcode=0(sync), len=12
    assert_eq!(u32::from_le_bytes(bytes[12..16].try_into().unwrap()), 1);
    let w2 = u32::from_le_bytes(bytes[16..20].try_into().unwrap());
    assert_eq!((w2 & 0xffff) as u16, 0, "opcode 应为 sync(0)");
    assert_eq!((w2 >> 16) as u16, 12, "sync 长度应为 12");
}

struct CS;
impl wayland_client::Dispatch<wayland_client::protocol::wl_registry::WlRegistry,
    wayland_client::globals::GlobalListContents> for CS {
    fn event(_: &mut Self, _: &wayland_client::protocol::wl_registry::WlRegistry,
        _: <wayland_client::protocol::wl_registry::WlRegistry as wayland_client::Proxy>::Event,
        _: &wayland_client::globals::GlobalListContents,
        _: &wayland_client::Connection, _: &wayland_client::QueueHandle<Self>) {}
}
