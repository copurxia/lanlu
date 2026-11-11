// lanlu ohos: ArkTS -> system-layer bridge.
//
// The window-level input filters (input_filter.cpp) need the OHOS *ArkTS*
// window id (window.getWindowProperties().id) and the window rect origin as
// the calibration seed. Only ArkTS can read those, so this module exposes
// startFilter(winId, originX, originY) to the generated Index.ets.
// libmain.so serves double duty: SDL dlopens it for SDL_main, and ArkTS
// imports it for this napi module (static registration, horizonshell-style).
#include "napi/native_api.h"
#include <dlfcn.h>
#include <database/pasteboard/oh_pasteboard.h>
#include <database/udmf/udmf.h>
#include <pthread.h>
#include <unistd.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <time.h>
#include <hilog/log.h>

#ifndef LOG_TAG
#define LOG_TAG "LANLU-NATIVE"
#endif
extern "C" int lanlu_set_surface_id(unsigned long long surface_id);
extern "C" int lanlu_stage_probe_png();
extern "C" int lanlu_push_input(int action, float x, float y, int key);
/* 输入/表面走协议（M6 第 1 步后文件桥已删） */
extern "C" int lanlu_lwp_send_key(const char* name, int down);
extern "C" int lanlu_lwp_send_text(const char* text);
extern "C" int lanlu_lwp_send_surface_available(unsigned long long handle, unsigned int w, unsigned int h);
extern "C" int lanlu_lwp_send_surface_changed(unsigned int w, unsigned int h);
extern "C" unsigned int lanlu_lwp_take_frame_request(void);
extern "C" int lanlu_lwp_take_ime_cursor_rect(int* x, int* y, int* w, int* h);
extern "C" int lanlu_lwp_take_cursor_shape(void);
extern "C" int lanlu_lwp_take_resize(int* w, int* h);
extern "C" int lanlu_lwp_take_ime_want(void);

/* 文本输入开关：-1=无变化 0=关 1=开 */
static napi_value LwpTakeImeWant(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_take_ime_want(), &out);
    return out;
}

extern "C" int lanlu_lwp_take_window_title(char* out, unsigned int cap);
extern "C" int lanlu_lwp_take_window_limits(int* out4);

/* 运行期窗口标题：没有待应用的标题返回空串 */
static napi_value LwpTakeWindowTitle(napi_env env, napi_callback_info info) {
    (void)info;
    char buf[256] = {0};
    napi_value out;
    if (lanlu_lwp_take_window_title(buf, sizeof(buf))) {
        napi_create_string_utf8(env, buf, NAPI_AUTO_LENGTH, &out);
    } else {
        napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &out);
    }
    return out;
}

/* 运行期尺寸约束：[minW,minH,maxW,maxH]；没有则空数组 */
static napi_value LwpTakeWindowLimits(napi_env env, napi_callback_info info) {
    (void)info;
    int v[4] = {0, 0, 0, 0};
    napi_value out;
    if (!lanlu_lwp_take_window_limits(v)) {
        napi_create_array_with_length(env, 0, &out);
        return out;
    }
    napi_create_array_with_length(env, 4, &out);
    napi_value e;
    for (int i = 0; i < 4; i++) {
        napi_create_int32(env, v[i], &e);
        napi_set_element(env, out, (uint32_t)i, e);
    }
    return out;
}

extern "C" void lanlu_lwp_attach_stats(unsigned int* frames, unsigned int* last_serial,
                                       unsigned int* backwards);

/* 壳侧帧统计：[帧数, 最近 attach serial, 倒退次数]（ArkTS 打日志用） */
static napi_value LwpAttachStats(napi_env env, napi_callback_info info) {
    (void)info;
    unsigned int f = 0, s = 0, b = 0;
    lanlu_lwp_attach_stats(&f, &s, &b);
    napi_value out, v;
    napi_create_array_with_length(env, 3, &out);
    napi_create_uint32(env, f, &v); napi_set_element(env, out, 0, v);
    napi_create_uint32(env, s, &v); napi_set_element(env, out, 1, v);
    napi_create_uint32(env, b, &v); napi_set_element(env, out, 2, v);
    return out;
}

/* 壳侧取待应用的窗口尺寸（缩放会话）；无新值返回空数组 */
static napi_value LwpTakeResize(napi_env env, napi_callback_info info) {
    (void)info;
    int w = 0, h = 0;
    napi_value out;
    if (!lanlu_lwp_take_resize(&w, &h)) {
        napi_create_array_with_length(env, 0, &out);
        return out;
    }
    napi_create_array_with_length(env, 2, &out);
    napi_value v;
    napi_create_int32(env, w, &v); napi_set_element(env, out, 0, v);
    napi_create_int32(env, h, &v); napi_set_element(env, out, 1, v);
    return out;
}

/* 壳侧取光标形状（-1 = 无新值） */
static napi_value LwpTakeCursorShape(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_take_cursor_shape(), &out);
    return out;
}

/* 壳侧取 IME 光标矩形（ArkTS 用来给输入法面板定位）；无新值时返回空数组 */
static napi_value LwpTakeImeCursorRect(napi_env env, napi_callback_info info) {
    (void)info;
    int x = 0, y = 0, w = 0, h = 0;
    napi_value out;
    if (!lanlu_lwp_take_ime_cursor_rect(&x, &y, &w, &h)) {
        napi_create_array_with_length(env, 0, &out);
        return out;
    }
    napi_create_array_with_length(env, 4, &out);
    napi_value v;
    int vals[4] = { x, y, w, h };
    for (int i = 0; i < 4; i++) {
        napi_create_int32(env, vals[i], &v);
        napi_set_element(env, out, (uint32_t)i, v);
    }
    return out;
}
extern "C" int lanlu_lwp_send_frame_done(unsigned int serial, unsigned long long time_ns);

/* vsync 回执：ArkTS 的 displaySync 每帧回调时调用 */
static napi_value LwpTakeFrameRequest(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_take_frame_request(), &out);
    return out;
}

static napi_value LwpFrameDone(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    int32_t serial = 0;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1) napi_get_value_int32(env, argv[0], &serial);
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    unsigned long long now = (unsigned long long)ts.tv_sec * 1000000000ull
        + (unsigned long long)ts.tv_nsec;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_frame_done((unsigned int)serial, now), &out);
    return out;
}
extern "C" unsigned int lanlu_lwp_take_clip_set(char* out, unsigned int cap);
extern "C" unsigned int lanlu_lwp_take_clip_get(void);

/* 引擎要求写系统剪贴板（lw_clipboard.set） */
/* 滚轮/触摸板：ArkUI 的 onAxisEvent -> lw_input.pointer_axis
 * （OHOS 的窗口鼠标过滤器收不到 AXIS，必须走 ArkUI 节点事件，见计划 §6.2/§M3） */
static napi_value LwpSendPointerAxis(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    double value = 0.0;
    int32_t axis = 0;   /* 0 = 垂直, 1 = 水平 */
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1) napi_get_value_double(env, argv[0], &value);
    if (argc >= 2) napi_get_value_int32(env, argv[1], &axis);
    napi_value out;
    napi_create_int32(env, lanlu_push_input(13, (float)value, (float)axis, 0), &out);
    return out;
}

static napi_value LwpTakeClipboardSet(napi_env env, napi_callback_info info) {
    (void)info;
    char buf[512] = {0};
    unsigned int n = lanlu_lwp_take_clip_set(buf, sizeof buf);
    napi_value out;
    napi_create_string_utf8(env, n > 0 ? buf : "", NAPI_AUTO_LENGTH, &out);
    return out;
}

/* 引擎请求读系统剪贴板（lw_clipboard.get）-> 返回 serial（0=无） */
static napi_value LwpTakeClipboardGet(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_take_clip_get(), &out);
    return out;
}

/* 壳的 XComponent 尺寸变化 -> lw_surface.changed（计划 §7.3：引擎据此重配 swapchain） */
static napi_value LwpSurfaceChanged(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    int32_t w = 0, h = 0;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 2) {
        napi_get_value_int32(env, argv[0], &w);
        napi_get_value_int32(env, argv[1], &h);
    }
    napi_value out;
    napi_create_int32(env, (w > 0 && h > 0)
        ? lanlu_lwp_send_surface_changed((unsigned int)w, (unsigned int)h) : 0, &out);
    return out;
}
static void push_key_name2(const char* name, const char* mod, int down);

/* 键盘事件 -> 协议通道（M6 第 1 步：文件桥回退已删除）。
 * 协议不可用时直接丢弃：没有退路了，静默丢比写一个没人读的文件更诚实。 */
static void push_key_name2(const char* name, const char* mod, int down) {
    (void)mod;
    (void)lanlu_lwp_send_key(name, down ? 1 : 0);
}

static void push_key_name(const char* name, const char* mod) {
    push_key_name2(name, mod, true);
    push_key_name2(name, mod, false);
}
extern "C" int lanlu_lgpu_test(unsigned long long surface_id, int width, int height);
extern "C" int lanlu_lgpu_wanted();
extern "C" int lgpu_pipeline_init(void* surface);
extern "C" int lgpu_frame_begin(void* surface, float r, float g, float b, float a);
extern "C" int lgpu_draw_rect(void* surface, float x, float y, float w, float h, float radius, float stroke, float r, float g, float b, float a);
extern "C" int lgpu_frame_end(void* surface);
extern "C" void* lgpu_texture_create(void* surface, unsigned int width, unsigned int height);
extern "C" int lgpu_texture_upload(void* surface, void* tex, unsigned int x, unsigned int y,
                                   unsigned int width, unsigned int height, const unsigned char* pixels,
                                   unsigned int stride);
extern "C" int lgpu_draw_texture(void* surface, void* tex, float dx, float dy, float dw, float dh,
                                 float u0, float v0, float u1, float v1,
                                 float r, float g, float b, float a);
extern "C" void lgpu_texture_destroy(void* tex);
extern "C" int lgpu_set_clip(void* surface, float x, float y, float w, float h);
extern "C" int lgpu_set_transform(void* surface, float sx, float sy, float ox, float oy);
// lgpu 上屏自检用到的全局句柄
static void* g_lgpu_surface = nullptr;
static void* g_lgpu_checker = nullptr;

extern "C" int lgpu_selftest(void* surface);
extern "C" int lgpu_selftest_text(void* surface, const unsigned char* font_path, unsigned long len);
extern "C" const char* lgpu_last_error(void);

#define LOGI(fmt, ...) do { char _b[256]; snprintf(_b, sizeof _b, fmt, ##__VA_ARGS__); OH_LOG_INFO(LOG_APP, "%{public}s", _b); } while (0)

#ifndef LOG_TAG
#define LOG_TAG "LANLU-NATIVE"
#endif

extern "C" int lanlu_register_filters(int32_t window_id);
extern "C" void lanlu_seed_origin(double x, double y);
// P5：这些状态原本定义在 sdl_main.c（SDL 入口，已不编译）。
__attribute__((visibility("default"))) volatile int g_lanlu_app_exited = 0;
__attribute__((visibility("default"))) volatile int g_lanlu_minimize_requested = 0;
__attribute__((visibility("default"))) volatile int g_dialog_kind = 0;
extern volatile int g_lanlu_minimize_requested;
extern volatile int g_dialog_kind;
typedef void (*SdlDialogCb)(void *userdata, const char * const *filelist, int filter);
extern "C" __attribute__((visibility("default"))) SdlDialogCb g_dialog_cb = nullptr;
extern "C" __attribute__((visibility("default"))) void *g_dialog_ud = nullptr;



// ---- 剪贴板（M6 第 2 步）--------------------------------------------------
// 原生 pasteboard 线程已删除：剪贴板只走 lw_clipboard.set/get，由 ArkTS 的
// pasteboard API 执行（更稳、且与协议同一条路径）。LANLU_NATIVE_CLIP 不再存在。

// ---- P5：引擎启动（不再依赖 SDL 的 SDL_main）---------------------------------
// 原来 libSDL3.so 的 OHOS glue 会调本库的 SDL_main，再由 sdl_main.c 起 Cangjie 引擎。
// 现在壳层不建 SDL XComponent，改由 ArkTS 显式调用 startEngine()。
// 引擎只能启动一次：Cangjie runtime 不支持二次 init（真机报
// "Cangjie runtime has been initialized and don't support init again" 后 abort）。
static std::atomic<bool> g_engine_started{false};

// LWP：协议通道库必须先于引擎、以 RTLD_GLOBAL 加载（docs/l-layer.md M0-4 结论：
// 晚加载或 RTLD_LOCAL 会让引擎解析不到符号，而且是**静默失败**——dlopen 成功、退出码 0）。
// 壳侧先建好通道，引擎侧 lwp_open 同名会拿到同一个实例。
static void* g_lwp_lib = nullptr;
static void lanlu_init_lwp(void) {
    g_lwp_lib = dlopen("liblwp_native.so", RTLD_NOW | RTLD_GLOBAL);
    LOGI("lwp: lib=%p err=%s", g_lwp_lib, g_lwp_lib ? "-" : dlerror());
    if (g_lwp_lib == nullptr) return;
    typedef int (*OpenFn)(const char*, unsigned int, void**);
    OpenFn open_fn = (OpenFn)dlsym(g_lwp_lib, "lwp_open");
    if (open_fn == nullptr) {
        LOGI("lwp: lwp_open 未导出");
        return;
    }
    void* ch = nullptr;
    int rc = open_fn("lanlu", 256, &ch);
    LOGI("lwp: lwp_open rc=%d ch=%p", rc, ch);
}

static void* lanlu_engine_thread(void* arg) {
    (void)arg;
    LOGI("engine thread: enter");
    lanlu_init_lwp();
    const char* engine = getenv("LANLU_ENGINE_SO");
    if (engine == nullptr) engine = "liblanlu_client_next.so";
    void* rt = dlopen("libcangjie-runtime.so", RTLD_NOW | RTLD_GLOBAL);
    LOGI("engine thread: runtime=%p err=%s", rt, rt ? "-" : dlerror());
    if (rt == nullptr) return nullptr;
    typedef void (*InitRuntimeFn)(void*);
    typedef void (*LoadLibFn)(const char*);
    typedef int (*MainFn)(void);
    InitRuntimeFn init = (InitRuntimeFn)dlsym(rt, "InitCJRuntime");
    LoadLibFn load = (LoadLibFn)dlsym(rt, "LoadCJLibraryWithInit");
    if (init == nullptr || load == nullptr) return nullptr;
    static char argbuf[1024];
    init((void*)argbuf);
    load(engine);
    void* eng = dlopen(engine, RTLD_NOW | RTLD_GLOBAL);
    LOGI("engine thread: engine=%p err=%s", eng, eng ? "-" : dlerror());
    if (eng == nullptr) return nullptr;
    MainFn m = (MainFn)dlsym(eng, "cj_app_main");
    LOGI("engine thread: cj_app_main=%p", (void*)m);
    if (m != nullptr) {
        m();
        g_lanlu_app_exited = 1;
    }
    return nullptr;
}

// libmain.so 加载即启动引擎（等价于原 SDL_main 的时机，不依赖 ArkTS 调用）。
// LANLU_NO_AUTOSTART=1 可关闭（调试用）。
__attribute__((constructor)) static void lanlu_autostart_engine(void) {
    const char* off = getenv("LANLU_NO_AUTOSTART");
    if (off != nullptr && off[0] == '1') return;
    if (g_engine_started.exchange(true)) return;
    LOGI("autostart: starting engine thread");
    pthread_t th;
    pthread_create(&th, nullptr, lanlu_engine_thread, nullptr);
}

static napi_value StartEngine(napi_env env, napi_callback_info info) {
    LOGI("startEngine called");
    napi_value out;
    if (g_engine_started.exchange(true)) {
        napi_create_int32(env, 1, &out);
        return out;
    }
    pthread_t th;
    const int prc = pthread_create(&th, nullptr, lanlu_engine_thread, nullptr);
    LOGI("startEngine: pthread_create rc=%d", prc);
    napi_create_int32(env, 0, &out);
    return out;
}
static napi_value StagePng(napi_env env, napi_callback_info info) {
    int n = lanlu_stage_probe_png();
    napi_value out;
    napi_create_int32(env, n, &out);
    return out;
}

static napi_value PushInput(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t action = 0; int32_t key = 0; double x = 0; double y = 0;
    if (argc >= 1) napi_get_value_int32(env, argv[0], &action);
    if (argc >= 2) napi_get_value_double(env, argv[1], &x);
    if (argc >= 3) napi_get_value_double(env, argv[2], &y);
    if (argc >= 4) napi_get_value_int32(env, argv[3], &key);
    lanlu_push_input(action, (float)x, (float)y, key);
    napi_value out;
    napi_create_int32(env, 0, &out);
    return out;
}

// ---- LWP 窗口（计划 §7）：ArkTS 侧的窗口事件入口 ----
extern "C" int lanlu_lwp_window_pump(void);
extern "C" int lanlu_lwp_send_window_created(unsigned int id, float scale, int ssd);
extern "C" int lanlu_lwp_send_window_configure(unsigned int w, unsigned int h, unsigned int state);
extern "C" int lanlu_lwp_send_app_resumed(void);
extern "C" int lanlu_lwp_send_app_paused(void);

extern "C" int lanlu_lwp_send_test_inject(unsigned int kind, int a, int b);
extern "C" int lanlu_lwp_send_test_capture(const char* path);

static napi_value LwpTestInject(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t kind = 0, a = 0, b = 0;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &kind);
    if (argc >= 2) napi_get_value_int64(env, argv[1], &a);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &b);
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_test_inject((unsigned int)kind, (int)a, (int)b), &out);
    return out;
}

static napi_value LwpTestCapture(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    char path[256] = {0};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, argv[0], path, sizeof path, &len);
    }
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_test_capture(path), &out);
    return out;
}

extern "C" unsigned int lanlu_lwp_take_capture_request(void);
extern "C" const char* lanlu_lwp_capture_path(void);
extern "C" unsigned int lanlu_lwp_window_state(void);
extern "C" unsigned int lanlu_lwp_take_window_state(void);

static napi_value LwpTakeWindowState(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_take_window_state(), &out);
    return out;
}
extern "C" unsigned int lanlu_lwp_take_close_request(void);
extern "C" int lanlu_lwp_take_title_buttons(unsigned int* out);
extern "C" int lanlu_lwp_send_title_buttons_rect(int right, int top, unsigned int w,
                                                 unsigned int h, int visible);
extern "C" int lanlu_lwp_send_window_close_request(void);
/* 壳 -> 引擎：系统关闭钮被点击（windowWillClose 拦截后转发）。语义同 xdg_toplevel.close。 */
static napi_value LwpSendCloseRequest(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_window_close_request(), &out);
    return out;
}

/* 引擎请求的三键配置：[visible, side, close_margin, spacing, button_size, color_mode]；
 * 没有待处理配置时返回空数组（ArkTS 每 400ms 轮询，语义同 lwpTakeWindowLimits）。 */
static napi_value LwpTakeTitleButtons(napi_env env, napi_callback_info info) {
    (void)info;
    unsigned int v[6] = {0, 0, 0, 0, 0, 0};
    napi_value out;
    if (!lanlu_lwp_take_title_buttons(v)) {
        napi_create_array_with_length(env, 0, &out);
        return out;
    }
    napi_create_array_with_length(env, 6, &out);
    napi_value e;
    for (int i = 0; i < 6; i++) {
        napi_create_uint32(env, v[i], &e);
        napi_set_element(env, out, (uint32_t)i, e);
    }
    return out;
}

/* 壳 -> 引擎：平台三键矩形（px）。ArkTS 从 getTitleButtonRect()/rectChange 拿到 vp 后换算。 */
static napi_value LwpTitleButtonRect(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value argv[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t right = 0, top = 0, w = 0, h = 0, visible = 0;
    if (argc >= 1) napi_get_value_int32(env, argv[0], &right);
    if (argc >= 2) napi_get_value_int32(env, argv[1], &top);
    if (argc >= 3) napi_get_value_int32(env, argv[2], &w);
    if (argc >= 4) napi_get_value_int32(env, argv[3], &h);
    if (argc >= 5) napi_get_value_int32(env, argv[4], &visible);
    napi_value out;
    napi_create_int32(env,
        lanlu_lwp_send_title_buttons_rect(right, top, (unsigned int)w, (unsigned int)h, visible), &out);
    return out;
}
extern "C" int lanlu_lwp_take_exit_code(void);
extern "C" unsigned int lanlu_lwp_dialog_request(void);
extern "C" unsigned int lanlu_lwp_dialog_serial(void);
extern "C" const char* lanlu_lwp_dialog_suggested(void);
extern "C" void lanlu_lwp_dialog_clear(void);
extern "C" int lanlu_lwp_send_dialog_result(unsigned int serial, const char* path);

static napi_value LwpTakeCapture(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_take_capture_request(), &out);
    return out;
}

static napi_value LwpCapturePath(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_string_utf8(env, lanlu_lwp_capture_path(), NAPI_AUTO_LENGTH, &out);
    return out;
}

static napi_value LwpWindowState(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_window_state(), &out);
    return out;
}

static napi_value LwpTakeClose(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_take_close_request(), &out);
    return out;
}

static napi_value LwpTakeExit(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_take_exit_code(), &out);
    return out;
}

extern "C" int lanlu_lwp_send_clipboard_text(unsigned int serial, const char* mime, const char* text);
extern "C" int lanlu_lwp_ready(void);

// 壳/ArkTS 判断协议是否可用：可用时就不再走文件桥（计划 §11 的「已短路」判据）
static napi_value LwpEnabled(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_ready(), &out);
    return out;
}

static napi_value LwpClipboardText(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    char mime[64] = {0}, text[256] = {0};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t serial = 0;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &serial);
    if (argc >= 2) { size_t l = 0; napi_get_value_string_utf8(env, argv[1], mime, sizeof mime, &l); }
    if (argc >= 3) { size_t l = 0; napi_get_value_string_utf8(env, argv[2], text, sizeof text, &l); }
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_clipboard_text((unsigned int)serial, mime, text), &out);
    return out;
}

static napi_value LwpDialogRequest(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_dialog_request(), &out);
    return out;
}

static napi_value LwpDialogSerial(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, (int)lanlu_lwp_dialog_serial(), &out);
    return out;
}

static napi_value LwpDialogSuggested(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_string_utf8(env, lanlu_lwp_dialog_suggested(), NAPI_AUTO_LENGTH, &out);
    return out;
}

static napi_value LwpDialogResult(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    char path[256] = {0};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t serial = 0;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &serial);
    if (argc >= 2) {
        size_t len = 0;
        napi_get_value_string_utf8(env, argv[1], path, sizeof path, &len);
    }
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_dialog_result((unsigned int)serial, path), &out);
    return out;
}

static napi_value LwpDialogClear(napi_env env, napi_callback_info info) {
    (void)info;
    lanlu_lwp_dialog_clear();
    napi_value out;
    napi_create_int32(env, 0, &out);
    return out;
}

static napi_value LwpWindowPump(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_window_pump(), &out);
    return out;
}

static napi_value LwpWindowCreated(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t id = 0;
    double scale = 1.0;
    bool ssd = false;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &id);
    if (argc >= 2) napi_get_value_double(env, argv[1], &scale);
    if (argc >= 3) napi_get_value_bool(env, argv[2], &ssd);
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_window_created((unsigned int)id, (float)scale, ssd ? 1 : 0), &out);
    return out;
}

static napi_value LwpWindowConfigure(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t w = 0, hgt = 0, st = 0;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &w);
    if (argc >= 2) napi_get_value_int64(env, argv[1], &hgt);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &st);
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_window_configure((unsigned int)w, (unsigned int)hgt, (unsigned int)st), &out);
    return out;
}

static napi_value LwpAppResumed(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_app_resumed(), &out);
    return out;
}

static napi_value LwpAppPaused(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out;
    napi_create_int32(env, lanlu_lwp_send_app_paused(), &out);
    return out;
}

extern "C" int lanlu_lwp_send_system_info(const char* tz, const char* lang, const char* font_dir,
                                          const char* home_dir, unsigned int api_level);

static void napiArgString(napi_env env, napi_value v, char* out, size_t cap) {
    out[0] = '\0';
    if (v == nullptr || cap == 0) return;
    size_t len = 0;
    if (napi_get_value_string_utf8(env, v, out, cap, &len) != napi_ok) out[0] = '\0';
}

static napi_value LwpSystemInfo(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char tz[64], lang[32], fonts[256], home[256];
    napiArgString(env, argc >= 1 ? argv[0] : nullptr, tz, sizeof tz);
    napiArgString(env, argc >= 2 ? argv[1] : nullptr, lang, sizeof lang);
    napiArgString(env, argc >= 3 ? argv[2] : nullptr, fonts, sizeof fonts);
    napiArgString(env, argc >= 4 ? argv[3] : nullptr, home, sizeof home);
    int64_t api = 0;
    if (argc >= 5) napi_get_value_int64(env, argv[4], &api);
    napi_value out;
    napi_create_int32(env,
        lanlu_lwp_send_system_info(tz, lang, fonts, home, (unsigned int)api), &out);
    return out;
}

static napi_value SetSurfaceId(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t sid = 0;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &sid);
    int rc = lanlu_set_surface_id((unsigned long long)sid);
    napi_value out;
    napi_create_int32(env, rc, &out);
    return out;
}

static napi_value LgpuTest(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t surface_id = 0; int32_t w = 0, h = 0;
    if (argc >= 1) napi_get_value_int64(env, argv[0], &surface_id);
    if (argc >= 2) napi_get_value_int32(env, argv[1], &w);
    if (argc >= 3) napi_get_value_int32(env, argv[2], &h);
        const int rc = lanlu_lgpu_test((unsigned long long)surface_id, (int)w, (int)h);
    napi_value out;
    napi_create_int32(env, rc, &out);
    return out;
}

static napi_value LgpuTextSelftest(napi_env env, napi_callback_info info) {
    int rc = 0;
    if (g_lgpu_surface != nullptr) {
        static const char kFont[] = "/system/fonts/HarmonyOS_Sans.ttf";
        rc = lgpu_selftest_text(g_lgpu_surface, (const unsigned char*)kFont, sizeof(kFont) - 1);
    }
    napi_value out;
    napi_create_int32(env, rc, &out);
    return out;
}

static napi_value LgpuLastError(napi_env env, napi_callback_info info) {
    const char* msg = lgpu_last_error();
    napi_value out;
    napi_create_string_utf8(env, msg != nullptr ? msg : "", NAPI_AUTO_LENGTH, &out);
    return out;
}

static napi_value InputProbeWanted(napi_env env, napi_callback_info info) {
    const char* v = getenv("LANLU_PROBE_INPUT");
    napi_value out;
    napi_create_int32(env, (v != nullptr && v[0] == '1') ? 1 : 0, &out);
    return out;
}

static napi_value LgpuMainWanted(napi_env env, napi_callback_info info) {
    // P5：默认就是我们自己的全尺寸 XComponent（L 层窗口 + lgpu 渲染）。
    // 需要老路径时设 LANLU_SHELL_SDL=1（SDL XComponent + SDL 渲染）。
    const char* legacy = getenv("LANLU_SHELL_SDL");
    const bool useLegacy = (legacy != nullptr && legacy[0] == '1');
    napi_value out;
    napi_create_int32(env, useLegacy ? 0 : 1, &out);
    return out;
}

static napi_value SetMainSurface(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double sid = 0, w = 0, h = 0;
    if (argc >= 1) napi_get_value_double(env, argv[0], &sid);
    if (argc >= 2) napi_get_value_double(env, argv[1], &w);
    if (argc >= 3) napi_get_value_double(env, argv[2], &h);
    char buf[64];
    snprintf(buf, sizeof(buf), "%.0f", sid);
    setenv("LANLU_MAIN_SURFACE_ID", buf, 1);
    snprintf(buf, sizeof(buf), "%.0f", w);
    setenv("LANLU_MAIN_W", buf, 1);
    snprintf(buf, sizeof(buf), "%.0f", h);
    setenv("LANLU_MAIN_H", buf, 1);
    // LWP（计划 §7.1）：surface 可用 + 尺寸（LANLU_LWP 未开时是空操作）
    (void)lanlu_lwp_send_surface_available((unsigned long long)sid, (unsigned int)w, (unsigned int)h);
    napi_value out;
    napi_create_int32(env, 0, &out);
    return out;
}

static napi_value LgpuWanted(napi_env env, napi_callback_info info) {
        napi_value out;
    napi_create_int32(env, lanlu_lgpu_wanted(), &out);
    return out;
}

extern "C" double lanlu_origin_x(void);
extern "C" double lanlu_origin_y(void);
extern "C" int lanlu_origin_ok(void);

static napi_value StartFilter(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t win_id = 0; double ox = 0, oy = 0;
    if (argc >= 1) napi_get_value_int32(env, argv[0], &win_id);
    if (argc >= 2) napi_get_value_double(env, argv[1], &ox);
    if (argc >= 3) napi_get_value_double(env, argv[2], &oy);
    lanlu_seed_origin(ox, oy);
    const int rc = lanlu_register_filters(win_id);
    // 取证：把过滤器实际使用的窗口原点写文件（应与 window_info.txt 的 rect 一致）。
    {
        const char* home = getenv("HOME");
        if (home != nullptr) {
            char p[512];
            snprintf(p, sizeof p, "%s/filter_origin.txt", home);
            FILE* f = fopen(p, "wb");
            if (f != nullptr) {
                fprintf(f, "ox=%.1f oy=%.1f calibrated=%d\n", lanlu_origin_x(), lanlu_origin_y(), lanlu_origin_ok());
                fclose(f);
            }
        }
    }
    napi_value out;
    napi_create_int32(env, rc, &out);
    return out;

}

// ---- text input (IME bridge) -------------------------------------------
// The OHOS SDL backend never emits SDL_EVENT_TEXT_INPUT, so the app cannot be
// typed into. ArkTS attaches the system input method and forwards committed
// text / editing commands here; we replay them as SDL events, which is exactly
// what the cross-platform UI layer already listens for.
/* 与 IME 提交走同一条路：把文本作为 SDL_EVENT_TEXT_INPUT 推入引擎。
 * 导出为非 static，便于联调钩子（LANLU_TEST_TEXT）直接验证整条链路。 */
extern "C" __attribute__((visibility("default"))) void lanlu_send_text(const char* s) {
    if (!s) return;
    // SDL 会拒收直接推送的 SDL_EVENT_TEXT_INPUT（真机实测 push=0），但 USER 事件通道可用
    // （应用的唤醒事件正是走这条路）。故把文本挂在 USER 事件上，由引擎侧翻译成 TextInput。
    // P5：文本走文件桥（引擎侧解析成 UiEvent.TextInput）；LANLU_LWP=1 时改走协议通道
    if (lanlu_lwp_send_text(s)) return;   /* 协议是唯一入口（M6 第 1 步） */
}

static napi_value SendText(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) return nullptr;
    size_t len = 0;
    if (napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len) != napi_ok || len == 0) return nullptr;
    char* buf = (char*)malloc(len + 1);
    if (!buf) return nullptr;
    napi_get_value_string_utf8(env, argv[0], buf, len + 1, &len);
    (void)lanlu_lwp_send_text(buf);   /* 协议是唯一入口（M6 第 1 步） */
    free(buf);
    return nullptr;
}

// P5：按键走文件桥（SDL 事件队列已移除）

static napi_value SendBackspace(napi_env env, napi_callback_info info) {
    push_key_name("Backspace", "");
    return nullptr;
}

static napi_value SendEnter(napi_env env, napi_callback_info info) {
    push_key_name("Enter", "");
    return nullptr;
}

static napi_value SendTab(napi_env env, napi_callback_info info) {
    push_key_name("Tab", "");
    return nullptr;
}

static napi_value SendDelete(napi_env env, napi_callback_info info) {
    push_key_name("Delete", "");
    return nullptr;
}

// Cursor moves and clipboard actions from the input method map onto the keys
// the cross-platform editor already understands.
static napi_value SendLeft(napi_env env, napi_callback_info info) {
    push_key_name("Left", "");
    return nullptr;
}

static napi_value SendRight(napi_env env, napi_callback_info info) {
    push_key_name("Right", "");
    return nullptr;
}

static napi_value SendUp(napi_env env, napi_callback_info info) {
    push_key_name("Up", "");
    return nullptr;
}

static napi_value SendDown(napi_env env, napi_callback_info info) {
    push_key_name("Down", "");
    return nullptr;
}

static napi_value SendCopy(napi_env env, napi_callback_info info) {
    push_key_name("C", "ctrl");
    return nullptr;
}

static napi_value SendPaste(napi_env env, napi_callback_info info) {
    push_key_name("V", "ctrl");
    return nullptr;
}

static napi_value SendCut(napi_env env, napi_callback_info info) {
    push_key_name("X", "ctrl");
    return nullptr;
}

static napi_value SendSelectAll(napi_env env, napi_callback_info info) {
    push_key_name("A", "ctrl");
    return nullptr;
}

// True once the engine loop has returned (window close from the app title bar).
static napi_value AppExited(napi_env env, napi_callback_info info) {
    napi_value out;
    napi_get_boolean(env, g_lanlu_app_exited != 0, &out);
    return out;
}

// Consume a pending minimize request from the engine title bar.
static napi_value TakeMinimize(napi_env env, napi_callback_info info) {
    napi_value out;
    napi_get_boolean(env, g_lanlu_minimize_requested != 0, &out);
    g_lanlu_minimize_requested = 0;
    return out;
}

// ---- file dialogs (system picker lives in ArkTS) ------------------------
// Returns the pending dialog kind (0 none, 1 open, 2 save, 3 folder) and clears
// it; the shell then resolves it with the platform picker.
static napi_value TakeFileDialog(napi_env env, napi_callback_info info) {
    napi_value out;
    const int kind = g_dialog_kind;
    g_dialog_kind = 0;
    napi_create_int32(env, kind, &out);
    return out;
}

// Resolve the pending dialog. paths are newline separated (empty = cancelled).
static napi_value CompleteFileDialog(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    SdlDialogCb cb = g_dialog_cb;
    void *ud = g_dialog_ud;
    g_dialog_cb = nullptr;
    g_dialog_ud = nullptr;
    if (!cb) return nullptr;
    size_t len = 0;
    if (argc < 1 || napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len) != napi_ok || len == 0) {
        cb(ud, nullptr, 0);  // cancelled
        return nullptr;
    }
    char *buf = (char*)malloc(len + 1);
    if (!buf) { cb(ud, nullptr, 0); return nullptr; }
    napi_get_value_string_utf8(env, argv[0], buf, len + 1, &len);
    char *list[64];
    int n = 0;
    char *cur = buf;
    while (cur && *cur && n < 63) {
        char *nl = strchr(cur, 10);
        if (nl) *nl = 0;
        list[n++] = cur;
        cur = nl ? nl + 1 : nullptr;
    }
    list[n] = nullptr;
    cb(ud, (const char * const *)list, 0);
    free(buf);
    return nullptr;
}

// 把 Want 参数注入进程环境变量（ArkTS 无法直接 setenv）。
// 用途：联调/自动化通过 `aa start --ps lanlu.env.KEY value` 控制引擎行为，
// 例如 LANLU_BENCH_ARCID 驱动播放基准；正常启动不传参数即无影响。
static napi_value SetEnv(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
        return nullptr;
    }
    char key[128] = {0};
    char val[2048] = {0};
    size_t klen = 0, vlen = 0;
    if (napi_get_value_string_utf8(env, argv[0], key, sizeof(key), &klen) != napi_ok || klen == 0) {
        return nullptr;
    }
    napi_get_value_string_utf8(env, argv[1], val, sizeof(val), &vlen);
    setenv(key, val, 1);
    return nullptr;
}

EXTERN_C_START

static napi_value ShellInit(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "startFilter", nullptr, StartFilter, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lgpuTest", nullptr, LgpuTest, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setSurfaceId", nullptr, SetSurfaceId, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startEngine", nullptr, StartEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stagePng", nullptr, StagePng, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pushInput", nullptr, PushInput, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lgpuWanted", nullptr, LgpuWanted, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lgpuMainWanted", nullptr, LgpuMainWanted, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "inputProbeWanted", nullptr, InputProbeWanted, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setMainSurface", nullptr, SetMainSurface, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lgpuLastError", nullptr, LgpuLastError, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lgpuTextSelftest", nullptr, LgpuTextSelftest, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "appExited", nullptr, AppExited, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "takeMinimizeRequest", nullptr, TakeMinimize, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "takeFileDialogRequest", nullptr, TakeFileDialog, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "completeFileDialog", nullptr, CompleteFileDialog, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpSystemInfo", nullptr, LwpSystemInfo, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpEnabled", nullptr, LwpEnabled, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpClipboardText", nullptr, LwpClipboardText, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeCaptureRequest", nullptr, LwpTakeCapture, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpCapturePath", nullptr, LwpCapturePath, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpWindowState", nullptr, LwpWindowState, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeWindowState", nullptr, LwpTakeWindowState, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeTitleButtons", nullptr, LwpTakeTitleButtons, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTitleButtonRect", nullptr, LwpTitleButtonRect, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeCloseRequest", nullptr, LwpTakeClose, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpSendCloseRequest", nullptr, LwpSendCloseRequest, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeExitCode", nullptr, LwpTakeExit, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpDialogRequest", nullptr, LwpDialogRequest, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpDialogSerial", nullptr, LwpDialogSerial, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpDialogSuggested", nullptr, LwpDialogSuggested, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpDialogResult", nullptr, LwpDialogResult, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpDialogClear", nullptr, LwpDialogClear, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTestInject", nullptr, LwpTestInject, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTestCapture", nullptr, LwpTestCapture, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpSurfaceChanged", nullptr, LwpSurfaceChanged, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeImeWant", nullptr, LwpTakeImeWant, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeWindowTitle", nullptr, LwpTakeWindowTitle, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeWindowLimits", nullptr, LwpTakeWindowLimits, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpAttachStats", nullptr, LwpAttachStats, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeResize", nullptr, LwpTakeResize, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeCursorShape", nullptr, LwpTakeCursorShape, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeImeCursorRect", nullptr, LwpTakeImeCursorRect, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeFrameRequest", nullptr, LwpTakeFrameRequest, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpFrameDone", nullptr, LwpFrameDone, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpSendPointerAxis", nullptr, LwpSendPointerAxis, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeClipboardSet", nullptr, LwpTakeClipboardSet, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpTakeClipboardGet", nullptr, LwpTakeClipboardGet, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpWindowPump", nullptr, LwpWindowPump, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpWindowCreated", nullptr, LwpWindowCreated, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpWindowConfigure", nullptr, LwpWindowConfigure, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpAppResumed", nullptr, LwpAppResumed, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "lwpAppPaused", nullptr, LwpAppPaused, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendText", nullptr, SendText, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendBackspace", nullptr, SendBackspace, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendEnter", nullptr, SendEnter, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendTab", nullptr, SendTab, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendDelete", nullptr, SendDelete, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendLeft", nullptr, SendLeft, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendRight", nullptr, SendRight, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendUp", nullptr, SendUp, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendDown", nullptr, SendDown, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendCopy", nullptr, SendCopy, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendPaste", nullptr, SendPaste, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendCut", nullptr, SendCut, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendSelectAll", nullptr, SendSelectAll, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setEnv", nullptr, SetEnv, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_shell_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = ShellInit,
    .nm_modname = "lanlushell",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

__attribute__((constructor)) static void ShellModuleRegister(void) {
    napi_module_register(&g_shell_module);
}

// ---- 系统剪贴板（原生）----------------------------------------------------
// ArkTS 的 pasteboard.setData 在本机被拒（13900002，非手势上下文）；这里直接用
// OH_Pasteboard C API 写入，并可由输入回调（手势上下文）或线程触发做对比。
#include <database/pasteboard/oh_pasteboard.h>
#include <database/udmf/udmf.h>
#include <database/udmf/uds.h>

extern "C" __attribute__((visibility("default"))) int lanlu_clipboard_write(const char* text) {
    if (!text) return -1;
    OH_Pasteboard* pb = OH_Pasteboard_Create();
    if (!pb) {
        LOGI("clip write: pasteboard create failed");
        return -2;
    }
    OH_UdsPlainText* udspt = OH_UdsPlainText_Create();
    OH_UdsPlainText_SetContent(udspt, text);
    OH_UdmfRecord* rec = OH_UdmfRecord_Create();
    OH_UdmfRecord_AddPlainText(rec, udspt);
    OH_UdmfData* data = OH_UdmfData_Create();
    OH_UdmfData_AddRecord(data, rec);
    int rc = OH_Pasteboard_SetData(pb, data);
    LOGI("clip write: rc=%d text=%s", rc, text);
    OH_UdmfData_Destroy(data);
    OH_UdmfRecord_Destroy(rec);
    OH_UdsPlainText_Destroy(udspt);
    OH_Pasteboard_Destroy(pb);
    return rc;
}

/* M6 第 2 步：剪贴板只走协议（lw_clipboard.set/get），本函数保留为空实现，
 * 供旧调用点（input_filter 的窗口回调）继续链接；下一轮连同调用点一起删。 */
extern "C" __attribute__((visibility("default"))) int lanlu_clip_flush_pending(void) {
    return 0;
}

// 读取系统剪贴板并写入文件（供引擎粘贴时使用）。
// 重要：必须从**窗口关联的输入回调**里调用——系统只对"窗口 + Ctrl+V 粘贴路径"放行，
// 普通线程读取会被 pasteboard_service 以 no permission 拒绝（windowPid=0）。
extern "C" __attribute__((visibility("default"))) int lanlu_clipboard_read_to(const char* path) {
    if (!path) return -1;
    OH_Pasteboard* pb = OH_Pasteboard_Create();
    if (!pb) return -2;
    int rc = 0;
    OH_UdmfData* data = OH_Pasteboard_GetData(pb, &rc);
    if (!data) {
        LOGI("clip read: getdata failed rc=%d", rc);
        OH_Pasteboard_Destroy(pb);
        return rc != 0 ? rc : -3;
    }
    std::string text;
    const unsigned int n = OH_UdmfData_GetRecordCount(data);
    for (unsigned int i = 0; i < n; ++i) {
        OH_UdmfRecord* rec = OH_UdmfData_GetRecord(data, i);
        if (!rec) continue;
        OH_UdsPlainText* pt = OH_UdsPlainText_Create();
        if (OH_UdmfRecord_GetPlainText(rec, pt) == 0) {
            const char* content = OH_UdsPlainText_GetContent(pt);
            if (content) { text += content; }
        }
        OH_UdsPlainText_Destroy(pt);
        if (!text.empty()) break;
    }
    OH_UdmfData_Destroy(data);
    OH_Pasteboard_Destroy(pb);
    FILE* f = fopen(path, "wb");
    if (f) { fwrite(text.data(), 1, text.size(), f); fclose(f); }
    LOGI("clip read: len=%zu -> %s", text.size(), path);
    return (int)text.size();
}

// ---- L 层渲染器上屏自检（wgpu）----------------------------------------------
// 由 ArkTS 把一块独立 XComponent 的 surfaceId 传进来：原生侧用
// OH_NativeWindow_CreateNativeWindowFromSurfaceId 拿到 OHNativeWindow*，
// 再交给 lgpu（wgpu/Vulkan，走 VK_OHOS_surface）清一帧并 present。
// 独立 XComponent 是为了不影响 SDL 正在用的主表面（过渡期两套并存）。
#include <native_window/external_window.h>

extern "C" {
void* lgpu_surface_create(void* native_window);
int lgpu_surface_init(void* surface, unsigned int width, unsigned int height);
int lgpu_present_clear(void* surface, float r, float g, float b, float a);
void lgpu_surface_destroy(void* surface);
const char* lgpu_last_error(void);
}


extern "C" __attribute__((visibility("default")))
int lanlu_lgpu_test(unsigned long long surface_id, int width, int height) {
    if (getenv("LANLU_PROBE_LGPU") == nullptr) {
        return 0;   // 未开启联调：静默跳过
    }
    // lwindow 自己开窗的模式：surface 由 Cangjie 侧创建，原生只负责公布 surfaceId
    // 合成一条事件，供 Cangjie 侧验证文件事件通道（lwindow 模式下也写）
    lanlu_push_input(9, (float)width * 0.5f, (float)height * 0.5f, 42);
    if (getenv("LANLU_PROBE_LWINDOW") != nullptr) {
        return 0;
    }
    OHNativeWindow* native_window = nullptr;
    int rc = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &native_window);
    if (rc != 0 || native_window == nullptr) {
        LOGI("lgpu test: create native window failed rc=%d", rc);
        return rc != 0 ? rc : -1;
    }
    if (g_lgpu_surface != nullptr) {
        if (g_lgpu_checker != nullptr) {
            lgpu_texture_destroy(g_lgpu_checker);
            g_lgpu_checker = nullptr;
        }
        lgpu_surface_destroy(g_lgpu_surface);
        g_lgpu_surface = nullptr;
    }
    g_lgpu_surface = lgpu_surface_create(native_window);
    if (g_lgpu_surface == nullptr) {
        LOGI("lgpu test: surface create failed: %s", lgpu_last_error());
        return -2;
    }
    int irc = lgpu_surface_init(g_lgpu_surface, (unsigned)width, (unsigned)height);
    if (irc != 0) {
        LOGI("lgpu test: surface init failed rc=%d: %s", irc, lgpu_last_error());
        return irc;
    }
    int prc = lgpu_pipeline_init(g_lgpu_surface);
    if (prc != 0) {
        LOGI("lgpu test: pipeline init failed rc=%d: %s", prc, lgpu_last_error());
        return prc;
    }
    // 一帧：深蓝底 + 白色圆角块 + 金色描边圆角块（便于截图做像素判定）
    lgpu_frame_begin(g_lgpu_surface, 0.05f, 0.08f, 0.20f, 1.0f);
    // 1) 圆角矩形（SDF）
    lgpu_draw_rect(g_lgpu_surface, 20.0f, 10.0f, 200.0f, 28.0f, 8.0f, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f);
    // 2) 纹理（红/绿棋盘）
    static unsigned char checker[64 * 64 * 4];
    static bool checker_ready = false;
    if (!checker_ready) {
        for (int yy = 0; yy < 64; ++yy) {
            for (int xx = 0; xx < 64; ++xx) {
                const bool red = ((xx / 8) + (yy / 8)) % 2 == 0;
                unsigned char* px = &checker[(yy * 64 + xx) * 4];
                px[0] = red ? 255 : 0;
                px[1] = red ? 0 : 255;
                px[2] = 0;
                px[3] = 255;
            }
        }
        checker_ready = true;
    }
    if (g_lgpu_checker == nullptr) {
        g_lgpu_checker = lgpu_texture_create(g_lgpu_surface, 64, 64);
        if (g_lgpu_checker != nullptr) {
            lgpu_texture_upload(g_lgpu_surface, g_lgpu_checker, 0, 0, 64, 64, checker, 64 * 4);
        }
    }
    if (g_lgpu_checker != nullptr) {
        lgpu_draw_texture(g_lgpu_surface, g_lgpu_checker, 20.0f, 48.0f, 120.0f, 40.0f,
                          0.0f, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f);
    }
    // 3) 裁剪：200x20 白条只显示左侧 80px
    lgpu_set_clip(g_lgpu_surface, 20.0f, 100.0f, 80.0f, 20.0f);
    lgpu_draw_rect(g_lgpu_surface, 20.0f, 100.0f, 200.0f, 20.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f);
    lgpu_set_clip(g_lgpu_surface, 0.0f, 0.0f, 0.0f, 0.0f);
    // 4) 变换：40x20 青色块整体右移 120px
    lgpu_set_transform(g_lgpu_surface, 1.0f, 1.0f, 120.0f, 0.0f);
    lgpu_draw_rect(g_lgpu_surface, 20.0f, 132.0f, 40.0f, 20.0f, 0.0f, 0.0f, 0.0f, 0.9f, 0.9f, 1.0f);
    lgpu_set_transform(g_lgpu_surface, 1.0f, 1.0f, 0.0f, 0.0f);
    prc = lgpu_frame_end(g_lgpu_surface);
    const int selftest = lgpu_selftest(g_lgpu_surface);
    LOGI("lgpu selftest (offscreen clip/transform): rc=%d %s", selftest,
         selftest == 0 ? "PASS" : (selftest & 4) ? "READBACK-FAIL" : "MISMATCH");
    // hilog 对本 tag 会丢行：结果同时落盘，便于 hdc 取回核对
    {
        const char* home = getenv("HOME");
        char path[512];
        snprintf(path, sizeof path, "%s/lgpu_selftest.txt", home != nullptr ? home : "/data/local/tmp");
        {
            FILE* f = fopen(path, "w");
            if (f != nullptr) {
                fprintf(f, "rc=%d\nclip=%s\ntransform=%s\nreadback=%s\n",
                        selftest,
                        (selftest & 1) ? "FAIL" : "PASS",
                        (selftest & 2) ? "FAIL" : "PASS",
                        (selftest & 4) ? "FAIL" : "PASS");
                fclose(f);
            }
        }
    }
    return selftest;
    LOGI("lgpu test: frame presented rc=%d (surfaceId=%llu %dx%d)", prc, surface_id, width, height);
    return prc;
}

extern "C" __attribute__((visibility("default")))
// 把已建好的 lgpu surface 指针交给 Cangjie 侧（LgpuCanvas 在真实窗口上绘制用）。
extern "C" __attribute__((visibility("default")))
void* lanlu_lgpu_surface() {
    return g_lgpu_surface;
}



// ---- 输入事件环形缓冲（纯 C，不用 std::deque/std::mutex）-------------------
// 上一版用 C++ 容器导致真机崩溃；这里用固定数组 + volatile 索引，单生产者/单消费者。
#define LQ_CAP 256
static volatile int g_qHead = 0;
static volatile int g_qTail = 0;
static int g_qAction[LQ_CAP];
static float g_qX[LQ_CAP];
static float g_qY[LQ_CAP];
static int g_qKey[LQ_CAP];

extern "C" __attribute__((visibility("default")))
int lanlu_push_input(int action, float x, float y, int key) {
    // 指针只走协议通道（M6 第 1 步：文件桥回退已删除）。
    extern int lanlu_lwp_send_pointer(int, float, float, int);
    return lanlu_lwp_send_pointer(action, x, y, key);
}


// 联调辅助：/data/local/tmp/probe.png 应用进程内读不到（沙箱），由 native 拷进应用目录。
extern "C" __attribute__((visibility("default")))
int lanlu_stage_probe_png() {
    const char* src = "/data/local/tmp/probe.png";
    const char* dst = "/data/storage/el2/base/files/probe.png";
    FILE* in = fopen(src, "rb");
    if (in == nullptr) return 0;
    fseek(in, 0, SEEK_END);
    long n = ftell(in);
    fseek(in, 0, SEEK_SET);
    if (n <= 0 || n > 8 * 1024 * 1024) { fclose(in); return 0; }
    unsigned char* buf = (unsigned char*)malloc((size_t)n);
    if (buf == nullptr) { fclose(in); return 0; }
    size_t got = fread(buf, 1, (size_t)n, in);
    fclose(in);
    FILE* out = fopen(dst, "wb");
    if (out == nullptr) { free(buf); return 0; }
    size_t wrote = fwrite(buf, 1, got, out);
    fclose(out);
    free(buf);
    return (int)wrote;
}

// 把 XComponent 的 surfaceId 写进进程环境，供引擎（Cangjie/lwindow）读取后自建窗口。
extern "C" __attribute__((visibility("default")))
int lanlu_set_surface_id(unsigned long long surface_id) {
    char buf[32];
    snprintf(buf, sizeof buf, "%llu", surface_id);
    setenv("LANLU_SURFACE_ID", buf, 1);
    LOGI("surface id published: %s", buf);
    return 0;
}

int lanlu_lgpu_wanted() {
    return getenv("LANLU_PROBE_LGPU") != nullptr ? 1 : 0;
}
