cmake_minimum_required(VERSION 3.5.0)
project(main)

# P5 完成态：壳（libmain.so）完全不依赖 SDL。
# - 窗口：ArkTS 的全尺寸 XComponent + 引擎侧 lgpu(wgpu/Vulkan) 渲染
# - 引擎启动：ArkTS 调 shell.startEngine() → 本库启动 Cangjie 引擎（不再经 SDL_main）
# - 输入：窗口过滤器 → 文件桥（指针/按键/文本）
# lwp_client.cpp 需要生成的协议头（packages/lwp/include，由 tools/lwp-gen.py 产出）
include_directories(__LWP_INCLUDE__)

add_library(main SHARED input_filter.cpp shell_napi.cpp lwp_client.cpp lwp_window.cpp)

# L 层渲染器（Rust staticlib，导出 C ABI）：lgpu 自检入口需要它。
set(LGPU_LIB "__LGPU_LIB__")
target_link_libraries(main PUBLIC "${LGPU_LIB}" ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libpasteboard.so ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libudmf.so hilog_ndk.z dl m pthread ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libace_ndk.z.so ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libace_napi.z.so ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libnative_window_manager.so ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libnative_window.so ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos/libohinput.so)
