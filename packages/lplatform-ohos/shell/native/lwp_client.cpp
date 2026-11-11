/* 壳侧 LWP 发送端（计划 §6）。把 ArkTS/输入过滤器产生的输入事件组包成 lw_input.* 消息，
 * 通过 liblwp_native.so 投递给引擎。
 *
 * 为什么用 dlsym 而不是链接：libmain.so 不引入新的 NEEDED（避免影响加载顺序），
 * 而 liblwp_native.so 由 shell_napi.cpp 在引擎之前以 RTLD_GLOBAL 加载（M0-4 结论）。
 * 这里再次 dlopen 同名库会拿到同一个句柄/实例，`lwp_open("lanlu")` 也返回同一个通道。
 *
 * 开关：环境变量 LANLU_LWP=1（与引擎侧 lwindow 的开关一致）。未开启时所有函数返回 0，
 * 调用方继续走原来的文件桥。
 *
 * 线格式来自 packages/lwp/include/lwp_protocol.h（由 tools/lwp-gen.py 从 IDL 生成）。
 */
#include <stdio.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lwp_protocol.h"

typedef int (*lwp_open_fn)(const char*, unsigned int, void**);
typedef int (*lwp_send_parts_fn)(void*, int, uint16_t, uint16_t, uint32_t, const void*, uint32_t);

static void lwp_send_hello(void);   /* 定义在下方；lwp_ready 首次打开通道后调用 */

static int g_lwp_state = 0;          /* 0=未尝试 1=可用 -1=不可用 */
static void* g_lwp_ch = nullptr;
static lwp_send_parts_fn g_send = nullptr;

static int lwp_ready(void) {
    if (g_lwp_state != 0) return g_lwp_state > 0;
    g_lwp_state = -1;
    /* 默认开启（与引擎侧一致）；LANLU_LWP=0 显式回退到文件桥，仅作排障退路。 */
    const char* on = getenv("LANLU_LWP");
    if (on != nullptr && on[0] == '0') return 0;
    void* lib = dlopen("liblwp_native.so", RTLD_NOW | RTLD_GLOBAL);
    if (lib == nullptr) return 0;
    lwp_open_fn open_fn = (lwp_open_fn)dlsym(lib, "lwp_open");
    g_send = (lwp_send_parts_fn)dlsym(lib, "lwp_send_parts");
    if (open_fn == nullptr || g_send == nullptr) return 0;
    int rc = open_fn("lanlu", 256, &g_lwp_ch);
    if (rc != 0 || g_lwp_ch == nullptr) return 0;
    g_lwp_state = 1;
    /* 检查器必须在 hello 之前打开：它只在**发送**路径上记录「本侧已握手」，
     * 顺序反了会把壳侧所有事件记成 notHandshaked（第 52 轮真机发现）。 */
    typedef int (*lwp_checker_fn)(void*, int);
    lwp_checker_fn checker = (lwp_checker_fn)dlsym(lib, "lwp_checker_enable");
    if (checker != nullptr) checker(g_lwp_ch, 0);
    /* 录制：LANLU_LWP_TRACE=/path/to/x.lwtrace（真机上取证用，计划 §16.3） */
    const char* trace_path = getenv("LANLU_LWP_TRACE");
    if (trace_path != nullptr && trace_path[0] != '\0') {
        typedef int (*lwp_trace_fn)(void*, const char*);
        lwp_trace_fn tr = (lwp_trace_fn)dlsym(lib, "lwp_trace_open");
        int trc = (tr != nullptr) ? tr(g_lwp_ch, trace_path) : -2;
        fprintf(stderr, "[LANLU-LWP] trace=%s sym=%d rc=%d\n",
                trace_path, tr != nullptr ? 1 : 0, trc);
    }
    lwp_send_hello();
    return 1;
}

/* 方向：LWP_EVENT（壳 -> 引擎） */
#define LANLU_LWP_EVENT 1
#define LANLU_LWP_REQUEST 0

/* 壳侧握手：core.hello。引擎收到后回 hello_ack，之后才允许发非 core 消息
 * （协议检查器规则，计划 §5.3）。必须在任何输入事件之前发。 */
static void lwp_send_hello(void) {
    const char* shell = "ohos";
    const char* os = "ohos";
    const size_t sl = strlen(shell), ol = strlen(os);
    uint8_t buf[LWP_LW_CORE_HELLO_SIZE + 64];
    memset(buf, 0, sizeof buf);
    lwp_lw_core_hello* h = (lwp_lw_core_hello*)buf;
    h->size = (uint32_t)(LWP_LW_CORE_HELLO_SIZE + sl + ol);
    h->protocol_major = LWP_PROTOCOL_MAJOR;
    h->protocol_minor = LWP_PROTOCOL_MINOR;
    h->shell_name.off = LWP_LW_CORE_HELLO_SIZE;
    h->shell_name.len = (uint16_t)sl;
    h->os_name.off = (uint16_t)(LWP_LW_CORE_HELLO_SIZE + sl);
    h->os_name.len = (uint16_t)ol;
    h->os_api_level = 26;   /* OHOS API level；壳侧不查系统版本，按构建 SDK 报 */
    /* 能力位（计划 §5.3）：只宣告壳**真的**支持的能力，引擎据此走降级路径。
     * 逐项对应 lplatform-ohos 已实现的功能，未实现的一律不置位。 */
    h->capabilities =
        LWP_CORE_CAPABILITIES_SERVER_SIDE_DECORATIONS |   /* 系统装饰已隐藏，标题栏自绘 */
        LWP_CORE_CAPABILITIES_CURSOR_SHAPES |             /* set_cursor 形状子集 */
        LWP_CORE_CAPABILITIES_IME_PREEDIT |               /* text-input preedit */
        LWP_CORE_CAPABILITIES_SOFT_KEYBOARD |             /* 输入法面板控制 */
        LWP_CORE_CAPABILITIES_FILE_DIALOG_SAVE |          /* dialog.save_file */
        LWP_CORE_CAPABILITIES_CLIPBOARD_READ_ASYNC |      /* clipboard.get 异步读 */
        LWP_CORE_CAPABILITIES_VSYNC |                     /* ArkTS displaySync 每帧回调 -> frame.done */
        LWP_CORE_CAPABILITIES_TITLE_BUTTONS |             /* set_title_buttons + rect 上报（decor=false 三键悬浮） */
        0ULL;
    memcpy(buf + LWP_LW_CORE_HELLO_SIZE, shell, sl);
    memcpy(buf + LWP_LW_CORE_HELLO_SIZE + sl, os, ol);
    g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE, 0,
           buf, h->size);
}

/* 给壳内其它模块（如 lwp_window.cpp）用的内部通道访问：避免各自 dlsym 一遍。
 * 返回 1 表示通道可用。 */
extern "C" __attribute__((visibility("default")))
int lanlu_lwp_ready(void) { return lwp_ready(); }

extern "C" __attribute__((visibility("default")))
int lanlu_lwp_send_raw(int dir, unsigned int iface, unsigned int opcode, unsigned int flags,
                       const void* body, unsigned int len) {
    if (!lwp_ready() || g_send == nullptr) return 0;
    return g_send(g_lwp_ch, dir, (uint16_t)iface, (uint16_t)opcode, flags, body, len) == 0;
}

typedef int (*lwp_recv_parts_fn)(void*, int, uint16_t*, uint16_t*, uint32_t*, uint64_t*,
                                 void*, uint32_t, uint32_t*);
static lwp_recv_parts_fn g_recv = nullptr;

extern "C" __attribute__((visibility("default")))
int lanlu_lwp_recv_raw(int dir, unsigned int* iface, unsigned int* opcode,
                       void* body, unsigned int cap, unsigned int* out_len) {
    if (!lwp_ready()) return -1;
    if (g_recv == nullptr) {
        void* lib = dlopen("liblwp_native.so", RTLD_NOW | RTLD_GLOBAL);
        if (lib == nullptr) return -1;
        g_recv = (lwp_recv_parts_fn)dlsym(lib, "lwp_recv_parts");
        if (g_recv == nullptr) return -1;
    }
    uint16_t i16 = 0, o16 = 0;
    uint32_t flags = 0, len = 0;
    uint64_t t = 0;
    int rc = g_recv(g_lwp_ch, dir, &i16, &o16, &flags, &t, body, cap, &len);
    if (rc != 0) { if (iface) *iface = 0; if (opcode) *opcode = 0; if (out_len) *out_len = 0; return rc; }
    if (iface) *iface = i16;
    if (opcode) *opcode = o16;
    if (out_len) *out_len = len;
    return 0;
}

/* 指针/滚轮/文本的实际发送。action 语义与原文件桥一致：
 * 1/11/21=按下 2/10/20=移动 3/12/22=抬起 13=滚轮（x=刻度，y=0 垂直 / 1 水平） */
extern "C" __attribute__((visibility("default")))
int lanlu_lwp_send_pointer(int action, float x, float y, int key) {
    if (!lwp_ready()) return 0;
    lwp_lw_input_pointer_motion evmotion;
    lwp_lw_input_pointer_button evbtn;
    switch (action) {
        case 1: case 11: case 21: {
            memset(&evbtn, 0, sizeof evbtn);
            evbtn.size = LWP_LW_INPUT_POINTER_BUTTON_SIZE;
            evbtn.x = x; evbtn.y = y;
            evbtn.button = (uint8_t)(key < 0 ? 0 : key);
            evbtn.down = 1;
            return g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_INPUT,
                          LWP_LW_INPUT_POINTER_BUTTON_OPCODE, 0, &evbtn, sizeof evbtn) == 0;
        }
        case 2: case 10: case 20: {
            memset(&evmotion, 0, sizeof evmotion);
            evmotion.size = LWP_LW_INPUT_POINTER_MOTION_SIZE;
            evmotion.x = x; evmotion.y = y;
            /* 高频移动标可丢弃 + 由调用方限流（计划 §6.2） */
            return g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_INPUT,
                          LWP_LW_INPUT_POINTER_MOTION_OPCODE, 2u /* LWP_F_DROPPABLE */,
                          &evmotion, sizeof evmotion) == 0;
        }
        case 3: case 12: case 22: {
            memset(&evbtn, 0, sizeof evbtn);
            evbtn.size = LWP_LW_INPUT_POINTER_BUTTON_SIZE;
            evbtn.x = x; evbtn.y = y;
            evbtn.button = (uint8_t)(key < 0 ? 0 : key);
            evbtn.down = 0;
            return g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_INPUT,
                          LWP_LW_INPUT_POINTER_BUTTON_OPCODE, 0, &evbtn, sizeof evbtn) == 0;
        }
        case 13: {
            lwp_lw_input_pointer_axis axis;
            memset(&axis, 0, sizeof axis);
            axis.size = LWP_LW_INPUT_POINTER_AXIS_SIZE;
            if (y > 0.5f) {          /* y=1 -> 水平 */
                axis.dx = x; axis.dy = 0.0f;
            } else {                 /* y=0 -> 垂直 */
                axis.dx = 0.0f; axis.dy = x;
            }
            return g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_INPUT,
                          LWP_LW_INPUT_POINTER_AXIS_OPCODE, 0, &axis, sizeof axis) == 0;
        }
        default:
            return 0;   /* 诊断码（91 等）不走协议 */
    }
}

/* IME 提交文本 */
extern "C" __attribute__((visibility("default")))
int lanlu_lwp_send_text(const char* text) {
    if (!lwp_ready() || text == nullptr) return 0;
    const size_t n = strlen(text);
    if (n == 0 || n > 200) return 0;          /* 单条内联上限内 */
    uint8_t buf[LWP_LW_INPUT_TEXT_INPUT_SIZE + 200];
    memset(buf, 0, sizeof buf);
    uint32_t total = (uint32_t)(LWP_LW_INPUT_TEXT_INPUT_SIZE + n);
    memcpy(buf, &total, 4);
    uint16_t off = LWP_LW_INPUT_TEXT_INPUT_SIZE;
    uint16_t len = (uint16_t)n;
    memcpy(buf + 4, &off, 2);
    memcpy(buf + 6, &len, 2);
    memcpy(buf + LWP_LW_INPUT_TEXT_INPUT_SIZE, text, n);
    return g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_INPUT,
                  LWP_LW_INPUT_TEXT_INPUT_OPCODE, 0, buf, total) == 0;
}

/* 键盘：名字 -> evdev 键码（计划 §6.1 的单表；鸿蒙 keyCode 也映射到这张表） */
static int keycode_from_name(const char* name) {
    if (name == nullptr || name[0] == '\0') return -1;
    if (strcmp(name, "Escape") == 0) return 1;
    if (strcmp(name, "Backspace") == 0) return 14;
    if (strcmp(name, "Tab") == 0) return 15;
    if (strcmp(name, "Enter") == 0) return 28;
    if (strcmp(name, "Space") == 0) return 57;
    if (strcmp(name, "Home") == 0) return 102;
    if (strcmp(name, "End") == 0) return 107;
    if (strcmp(name, "Delete") == 0) return 111;
    if (strcmp(name, "Up") == 0) return 103;
    if (strcmp(name, "Left") == 0) return 105;
    if (strcmp(name, "Right") == 0) return 106;
    if (strcmp(name, "Down") == 0) return 108;
    if (name[1] == '\0') {
        char c = name[0];
        if (c >= 'a' && c <= 'z') return 16 + (c - 'a');          /* q..p 连续段之外也能落 RawScancode */
        if (c >= '0' && c <= '9') return 2 + ((c - '0' + 9) % 10); /* evdev 1..10 是 1..9,0 */
    }
    return -1;
}

extern "C" __attribute__((visibility("default")))
int lanlu_lwp_send_key(const char* name, int down) {
    if (!lwp_ready()) return 0;
    int code = keycode_from_name(name);
    if (code < 0) return 0;
    lwp_lw_input_key ev;
    memset(&ev, 0, sizeof ev);
    ev.size = LWP_LW_INPUT_KEY_SIZE;
    ev.keycode = (uint32_t)code;
    ev.down = down ? 1 : 0;
    return g_send(g_lwp_ch, LANLU_LWP_EVENT, LWP_IFACE_LW_INPUT,
                  LWP_LW_INPUT_KEY_OPCODE, 0, &ev, sizeof ev) == 0;
}
