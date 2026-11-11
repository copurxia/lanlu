//! 链接 liblwp_native.so（协议通道）。宿主构建默认用 `packages/lwp/lib`；
//! 交叉编译 / 机林可通过 `LWP_LIB_DIR` 覆盖（与仓颉侧 `LWP_LIB_DIR` 同名同义）。
use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let dir = match std::env::var("LWP_LIB_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => manifest.parent().unwrap().join("lwp").join("lib"),
    };
    println!("cargo:rustc-link-search=native={}", dir.display());
    println!("cargo:rustc-link-lib=dylib=lwp_native");
    // 运行期需要能找到 .so：把目录写进 rpath，省掉每次手设 LD_LIBRARY_PATH
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    println!("cargo:rerun-if-env-changed=LWP_LIB_DIR");
}
