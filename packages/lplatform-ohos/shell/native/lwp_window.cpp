/* 壳侧窗口/应用生命周期发送端 + 请求泵（计划 §7、§9.1）。
 *
 * 职责：
 *   - ArkTS 侧窗口事件（创建完成、尺寸变化、关闭请求、焦点） → lw_window / lw_app 消息；
 *   - 泵：把引擎发来的请求（window.create / ack_configure / frame.request）取出来，
 *     供 ArkTS 轮询读取（真机上 ArkTS 定时器调 lanlu_lwp_window_pump()）。
 *
 * 为什么用泵而不是回调线程：ArkTS 的 UI 线程边界很硬，回调进 ArkTS 需要 napi env，
 * 在引擎线程里调会踩线程断言。轮询 + 原子量最稳妥，代价是延迟一个定时器周期（约 16ms）。
 */
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#if __has_include(<hilog/log.h>)
#include <hilog/log.h>
#define LANLU_HAVE_HILOG 1
#endif

#include <stdio.h>
#if __has_include(<hilog/log.h>)
#include <hilog/log.h>
#define LANLU_HAVE_HILOG 1
#endif

#include "lwp.h"
#include "lwp_protocol.h"

/* 壳侧日志：设备上用 hilog，宿主自测（无 OHOS SDK 头）退回 stderr。
 * 注意 `%{public}s` 只在 hilog 下有效，所以调用点统一传普通 %s / %d。 */
#ifdef LANLU_HAVE_HILOG
#define LOGI_LWP(fmt, ...) OH_LOG_INFO(LOG_APP, "[LANLU-LWP] " fmt, ##__VA_ARGS__)
#else
#define LOGI_LWP(fmt, ...) fprintf(stderr, "[LANLU-LWP] " fmt "\n", ##__VA_ARGS__)
#endif

/* 原生输入法桥（text_input.cpp）与输入过滤器共享的窗口原点 */
extern "C" {
#ifdef LWP_HOST_SELFTEST
void lanlu_ime_enable(int32_t window_id, uint32_t input_type, uint32_t enter_key, int show_soft) {
    (void)window_id; (void)input_type; (void)enter_key; (void)show_soft;
}
void lanlu_ime_disable(void) {}
void lanlu_ime_set_cursor_rect(int32_t x, int32_t y, int32_t w, int32_t h, double origin_x, double origin_y) {
    (void)x; (void)y; (void)w; (void)h; (void)origin_x; (void)origin_y;
}
double lanlu_origin_x(void) { return 0.0; }
double lanlu_origin_y(void) { return 0.0; }
#else
void lanlu_ime_enable(int32_t window_id, uint32_t input_type, uint32_t enter_key, int show_soft);
void lanlu_ime_disable(void);
void lanlu_ime_set_cursor_rect(int32_t x, int32_t y, int32_t w, int32_t h, double origin_x, double origin_y);
double lanlu_origin_x(void);
double lanlu_origin_y(void);
#endif
}
/* 由 shell_napi.cpp 在窗口就绪时设置（ArkTS 的 window id 与是否弹软键盘） */
static int32_t g_win_id_for_ime = -1;
static int g_show_soft_keyboard = 0;
extern "C" __attribute__((visibility("default")))
void lanlu_ime_set_window(int32_t window_id, int show_soft) {
    g_win_id_for_ime = window_id;
    g_show_soft_keyboard = show_soft;
}

extern "C" {
int lanlu_lwp_ready(void);
int lanlu_lwp_send_raw(int dir, unsigned int iface, unsigned int opcode, unsigned int flags,
                       const void* body, unsigned int len);
int lanlu_lwp_recv_raw(int dir, unsigned int* iface, unsigned int* opcode,
                       void* body, unsigned int cap, unsigned int* out_len);
}

#define LWP_SHELL_EVENT 1

static double g_ime_origin_x = 0.0;
static double g_ime_origin_y = 0.0;
static void refresh_ime_origin(void) {
    g_ime_origin_x = lanlu_origin_x();
    g_ime_origin_y = lanlu_origin_y();
}

/* 泵取到的最近状态（ArkTS 读这些 getter） */
static volatile unsigned int g_window_id = 0;
static volatile unsigned int g_scale_milli = 0;      /* 缩放 ×1000，避免浮点在原子量上 */
static volatile unsigned int g_ssd = 0;
static volatile unsigned int g_ack_serial = 0;
/* 交互式缩放会话：引擎发 begin_resize 后，指针移动由 input_filter 换算成新尺寸 */
/* 文本输入开关（引擎 text_input.enable/disable）：-1=无 0=关 1=开 */
static volatile int g_ime_want = -1;
static volatile int g_resize_edges = 0;       /* 0 = 不在缩放；位同 xdg-shell */
static volatile int g_resize_start_w = 0, g_resize_start_h = 0;
static volatile int g_resize_pending_w = 0, g_resize_pending_h = 0;
static volatile int g_win_w = 0, g_win_h = 0;
static volatile unsigned int g_frame_serial = 0;
/* surface.attach 消费：帧计数与最近一次 serial（计划 §7.3，OHOS 走直渲染但 serial 仍可用） */
static volatile unsigned int g_attach_last_serial = 0;
static volatile unsigned int g_attach_frames = 0;
static volatile unsigned int g_attach_backwards = 0;
/* 引擎下发的光标矩形（窗口坐标），IME 面板据此定位 */
static volatile int g_ime_cursor_x = 0, g_ime_cursor_y = 0, g_ime_cursor_w = 0, g_ime_cursor_h = 0;
static volatile int g_ime_cursor_pending = 0;
/* 引擎请求的光标形状（见文档 §7.5 的编号表） */
static volatile int g_cursor_shape = -1;
/* 运行期标题 / 尺寸约束（引擎 window.set_title / set_min_max） */
static char g_pending_title[256] = {0};
static int g_pending_title_flag = 0;
static int g_limits[4] = {0, 0, 0, 0};   /* min_w, min_h, max_w, max_h */
static int g_pending_limits_flag = 0;
static volatile unsigned int g_create_pending = 0;
static char g_create_title[128];
static char g_logbuf[256];
static char g_clip_set[512];
static volatile int g_clip_set_pending = 0;
static volatile unsigned int g_clip_get_serial = 0;   /* 0 = 无待处理 */
static volatile unsigned int g_capture_pending = 0;
static char g_capture_path[192];
static volatile unsigned int g_window_state = 0;   /* set_state 请求的 state 位 */
static volatile unsigned int g_close_requested = 0;
/* 引擎请求的三键配置（docs/lwindow-title-buttons-plan.md）：
 * [visible, side, close_margin, spacing, button_size, color_mode] */
static unsigned int g_title_buttons_cfg[6] = {0, 0, 0, 0, 0, 0};
static volatile int g_title_buttons_pending = 0;
static volatile int g_exit_code = -1;
static volatile unsigned int g_dialog_pending = 0;   /* 0=无 1=open 2=save */
static volatile unsigned int g_dialog_serial = 0;
static char g_dialog_suggested[128];
static volatile unsigned int g_close_pending = 0;

static void put_u32(uint8_t* b, int off, uint32_t v) {
    b[off] = (uint8_t)(v & 0xFF);
    b[off + 1] = (uint8_t)((v >> 8) & 0xFF);
    b[off + 2] = (uint8_t)((v >> 16) & 0xFF);
    b[off + 3] = (uint8_t)((v >> 24) & 0xFF);
}

static uint32_t get_u32(const uint8_t* b, int off) {
    return (uint32_t)b[off] | ((uint32_t)b[off + 1] << 8) |
           ((uint32_t)b[off + 2] << 16) | ((uint32_t)b[off + 3] << 24);
}

extern "C" {

int lanlu_lwp_send_app_started(unsigned int app_id) {
    uint8_t b[8];
    memset(b, 0, sizeof b);
    put_u32(b, 0, 8);
    put_u32(b, 4, app_id);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_APP, LWP_LW_APP_STARTED_OPCODE, 0, b, 8);
}

int lanlu_lwp_send_app_resumed(void) {
    uint8_t b[4];
    put_u32(b, 0, 4);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_APP, LWP_LW_APP_RESUMED_OPCODE, 0, b, 4);
}

int lanlu_lwp_send_app_paused(void) {
    uint8_t b[4];
    put_u32(b, 0, 4);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_APP, LWP_LW_APP_PAUSED_OPCODE, 0, b, 4);
}

int lanlu_lwp_send_window_created(unsigned int id, float scale, int ssd) {
    uint8_t b[LWP_LW_WINDOW_CREATED_SIZE];
    memset(b, 0, sizeof b);
    put_u32(b, 0, LWP_LW_WINDOW_CREATED_SIZE);
    put_u32(b, 4, id);
    memcpy(b + 8, &scale, 4);           /* f32 按位写入（不能做数值转换） */
    b[12] = ssd ? 1 : 0;
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CREATED_OPCODE,
                              0, b, sizeof b);
}

int lanlu_lwp_send_window_configure(unsigned int w, unsigned int h, unsigned int state) {
    uint8_t b[LWP_LW_WINDOW_CONFIGURE_SIZE];
    memset(b, 0, sizeof b);
    put_u32(b, 0, LWP_LW_WINDOW_CONFIGURE_SIZE);
    put_u32(b, 4, w);
    put_u32(b, 8, h);
    put_u32(b, 12, state);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CONFIGURE_OPCODE,
                              0, b, sizeof b);
}

int lanlu_lwp_send_window_close_request(void) {
    uint8_t b[4];
    put_u32(b, 0, 4);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_WINDOW,
                              LWP_LW_WINDOW_CLOSE_REQUEST_OPCODE, 0, b, 4);
}

/* 壳 -> 引擎：平台三键矩形（窗口局部 px）+ 可见性。docs/lwindow-title-buttons-plan.md */
int lanlu_lwp_send_title_buttons_rect(int right, int top, unsigned int w, unsigned int h, int visible) {
    uint8_t b[LWP_LW_WINDOW_TITLE_BUTTONS_RECT_SIZE];
    memset(b, 0, sizeof b);
    put_u32(b, 0, LWP_LW_WINDOW_TITLE_BUTTONS_RECT_SIZE);
    put_u32(b, 4, (uint32_t)right);
    put_u32(b, 8, (uint32_t)top);
    put_u32(b, 12, w);
    put_u32(b, 16, h);
    b[20] = visible ? 1 : 0;
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_WINDOW,
                              LWP_LW_WINDOW_TITLE_BUTTONS_RECT_OPCODE, 0, b, sizeof b);
}

int lanlu_lwp_send_window_focus(int focused) {
    uint8_t b[5];
    memset(b, 0, sizeof b);
    put_u32(b, 0, 5);
    b[4] = focused ? 1 : 0;
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_FOCUS_OPCODE,
                              0, b, 5);
}

int lanlu_lwp_send_frame_done(unsigned int serial, unsigned long long time_ns) {
    uint8_t b[LWP_LW_FRAME_DONE_SIZE];
    memset(b, 0, sizeof b);
    put_u32(b, 0, LWP_LW_FRAME_DONE_SIZE);
    put_u32(b, 4, serial);
    for (int i = 0; i < 8; i++) b[8 + i] = (uint8_t)((time_ns >> (8 * i)) & 0xFF);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_FRAME, LWP_LW_FRAME_DONE_OPCODE,
                              0, b, sizeof b);
}

int lanlu_lwp_send_surface_available(unsigned long long handle, unsigned int w, unsigned int h) {
    g_win_w = (int)w;
    g_win_h = (int)h;
    uint8_t b[LWP_LW_SURFACE_AVAILABLE_SIZE];
    memset(b, 0, sizeof b);
    put_u32(b, 0, LWP_LW_SURFACE_AVAILABLE_SIZE);
    for (int i = 0; i < 8; i++) b[4 + i] = (uint8_t)((handle >> (8 * i)) & 0xFF);
    put_u32(b, 12, w);
    put_u32(b, 16, h);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_SURFACE,
                              LWP_LW_SURFACE_AVAILABLE_OPCODE, 0, b, sizeof b);
}

/* 缩放会话锚点（会话内第一个指针位置）。必须是文件级：resize_end 要能重置它，
 * 之前是函数内 static，第二次拖边会沿用第一次的锚点，窗口一按就跳（评审 W5）。 */
static int g_resize_anchor_x = -1, g_resize_anchor_y = -1;
#define anchor_x g_resize_anchor_x
#define anchor_y g_resize_anchor_y

/* input_filter 调用：缩放会话中把指针位移换算成窗口新尺寸 */
void lanlu_lwp_resize_track(int x, int y) {
    if (!g_resize_edges) return;
    if (anchor_x < 0) { anchor_x = x; anchor_y = y; return; }
    int dx = x - anchor_x, dy = y - anchor_y;
    int w = g_resize_start_w, h = g_resize_start_h;
    if (g_resize_edges & 8) { w = g_resize_start_w + dx; }        /* 右 */
    if (g_resize_edges & 4) { w = g_resize_start_w - dx; }        /* 左 */
    if (g_resize_edges & 2) { h = g_resize_start_h + dy; }        /* 下 */
    if (g_resize_edges & 1) { h = g_resize_start_h - dy; }        /* 上 */
    if (w < 400) w = 400;
    if (h < 300) h = 300;
    g_resize_pending_w = w;
    g_resize_pending_h = h;
}

/* 结束缩放会话（松手时由 input_filter 调用） */
void lanlu_lwp_resize_end(void) {
    g_resize_edges = 0;
    g_resize_anchor_x = -1;
    g_resize_anchor_y = -1;
}
#undef anchor_x
#undef anchor_y

/* 一次性取走"文本输入开关"：-1 无变化，0 关闭，1 打开 */
int lanlu_lwp_take_ime_want(void) {
    int v = g_ime_want;
    g_ime_want = -1;
    return v;
}

/* 一次性取走待应用的标题；返回 0 表示无 */
int lanlu_lwp_take_window_title(char* out, unsigned int cap) {
    if (!g_pending_title_flag) return 0;
    g_pending_title_flag = 0;
    unsigned int n = (unsigned int)strlen(g_pending_title);
    if (n >= cap) n = cap - 1;
    memcpy(out, g_pending_title, n);
    out[n] = 0;
    return 1;
}

/* 一次性取走待应用的尺寸约束 [minW,minH,maxW,maxH]；返回 0 表示无 */
int lanlu_lwp_take_window_limits(int* out4) {
    if (!g_pending_limits_flag) return 0;
    g_pending_limits_flag = 0;
    for (int i = 0; i < 4; i++) out4[i] = g_limits[i];
    return 1;
}

/* 帧统计（供 ArkTS 打日志：C 侧 LOGI_LWP 在真机上不落 hilog） */
void lanlu_lwp_attach_stats(unsigned int* frames, unsigned int* last_serial, unsigned int* backwards) {
    if (frames) *frames = g_attach_frames;
    if (last_serial) *last_serial = g_attach_last_serial;
    if (backwards) *backwards = g_attach_backwards;
}

/* 一次性取走待应用的窗口尺寸；返回 1 表示有新值 */
int lanlu_lwp_take_resize(int* w, int* h) {
    if (g_resize_pending_w <= 0 || g_resize_pending_h <= 0) return 0;
    if (w) *w = g_resize_pending_w;
    if (h) *h = g_resize_pending_h;
    g_resize_pending_w = 0;
    g_resize_pending_h = 0;
    return 1;
}

int lanlu_lwp_send_surface_changed(unsigned int w, unsigned int h) {
    g_win_w = (int)w;
    g_win_h = (int)h;
    uint8_t b[LWP_LW_SURFACE_CHANGED_SIZE];
    memset(b, 0, sizeof b);
    put_u32(b, 0, LWP_LW_SURFACE_CHANGED_SIZE);
    put_u32(b, 4, w);
    put_u32(b, 8, h);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_SURFACE,
                              LWP_LW_SURFACE_CHANGED_OPCODE, 0, b, sizeof b);
}

int lanlu_lwp_send_surface_will_destroy(void) {
    uint8_t b[4];
    put_u32(b, 0, 4);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_SURFACE,
                              LWP_LW_SURFACE_WILL_DESTROY_OPCODE, 0, b, 4);
}

int lanlu_lwp_send_surface_hidden(void) {
    uint8_t b[4];
    put_u32(b, 0, 4);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_SURFACE,
                              LWP_LW_SURFACE_HIDDEN_OPCODE, 0, b, 4);
}

/* system.info：时区/语言/字体目录/家目录/API 级别（计划 §8） */
int lanlu_lwp_send_system_info(const char* tz, const char* lang, const char* font_dir,
                               const char* home_dir, unsigned int api_level) {
    const char* vals[4] = {tz ? tz : "", lang ? lang : "", font_dir ? font_dir : "", home_dir ? home_dir : ""};
    size_t lens[4];
    uint32_t total = LWP_LW_SYSTEM_INFO_SIZE;
    for (int i = 0; i < 4; i++) {
        lens[i] = strlen(vals[i]);
        if (lens[i] > 200) lens[i] = 200;
        total += (uint32_t)lens[i];
    }
    uint8_t buf[LWP_LW_SYSTEM_INFO_SIZE + 4 * 200];
    memset(buf, 0, sizeof buf);
    put_u32(buf, 0, total);
    uint32_t off = LWP_LW_SYSTEM_INFO_SIZE;
    for (int i = 0; i < 4; i++) {
        uint16_t o = (uint16_t)off, l = (uint16_t)lens[i];
        memcpy(buf + 4 + i * 4, &o, 2);
        memcpy(buf + 6 + i * 4, &l, 2);
        memcpy(buf + off, vals[i], lens[i]);
        off += (uint32_t)lens[i];
    }
    put_u32(buf, 20, api_level);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_SYSTEM, LWP_LW_SYSTEM_INFO_OPCODE,
                              0, buf, total);
}

int lanlu_lwp_send_test_inject(unsigned int kind, int a, int b) {
    uint8_t b2[LWP_LW_TEST_INJECT_SIZE];
    memset(b2, 0, sizeof b2);
    put_u32(b2, 0, LWP_LW_TEST_INJECT_SIZE);
    put_u32(b2, 4, kind);
    put_u32(b2, 8, (uint32_t)a);
    put_u32(b2, 12, (uint32_t)b);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_TEST, LWP_LW_TEST_INJECT_OPCODE,
                              0, b2, sizeof b2);
}

int lanlu_lwp_send_test_capture(const char* path) {
    if (path == nullptr) return 0;
    size_t n = strlen(path);
    if (n == 0 || n > 200) return 0;
    uint8_t buf[LWP_LW_TEST_CAPTURE_SIZE + 200];
    memset(buf, 0, sizeof buf);
    uint32_t total = (uint32_t)(LWP_LW_TEST_CAPTURE_SIZE + n);
    put_u32(buf, 0, total);
    uint16_t off = LWP_LW_TEST_CAPTURE_SIZE, len = (uint16_t)n;
    memcpy(buf + 4, &off, 2);
    memcpy(buf + 6, &len, 2);
    memcpy(buf + LWP_LW_TEST_CAPTURE_SIZE, path, n);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_TEST, LWP_LW_TEST_CAPTURE_OPCODE,
                              0, buf, total);
}

/* 泵：取引擎请求（REQUEST 方向）。返回本次处理条数；-1 表示通道不可用。 */
int lanlu_lwp_window_pump(void) {
    if (!lanlu_lwp_ready()) return -1;
    int n = 0;
    for (;;) {
        uint8_t body[LWP_INLINE_MAX];
        unsigned int iface = 0, opcode = 0, len = 0;
        int rc = lanlu_lwp_recv_raw(0 /* REQUEST */, &iface, &opcode, body, sizeof body, &len);
        if (rc != 0) break;
        n++;
        if (iface == LWP_IFACE_LW_WINDOW && opcode == LWP_LW_WINDOW_CREATE_OPCODE) {
            /* title 是 (u16 off,u16 len) 相对消息体起点；offsets 固定为 4 */
            unsigned int off = (unsigned int)body[4] | ((unsigned int)body[5] << 8);
            unsigned int tl = (unsigned int)body[6] | ((unsigned int)body[7] << 8);
            if (tl >= sizeof g_create_title) tl = sizeof g_create_title - 1;
            if (off + tl <= len) {
                memcpy(g_create_title, body + off, tl);
                g_create_title[tl] = '\0';
            }
            g_window_id = get_u32(body, 8 + tl);   /* width 紧跟标题之后 */
            g_create_pending = 1;
        } else if (iface == LWP_IFACE_LW_WINDOW && opcode == LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE) {
            g_ack_serial = get_u32(body, 4);
        } else if (iface == LWP_IFACE_LW_SURFACE &&
                   opcode == LWP_LW_SURFACE_ATTACH_OPCODE && len >= 24) {
            unsigned int serial = get_u32(body, 20);
            if (serial <= g_attach_last_serial) {
                g_attach_backwards++;   /* 理论上不该发生：引擎侧检查器已保证单调 */
            }
            g_attach_last_serial = serial;
            g_attach_frames++;
            if ((g_attach_frames % 120) == 1) {
                LOGI_LWP("frames=%u lastAttachSerial=%u backwards=%u",
                         g_attach_frames, serial, g_attach_backwards);
            }
        } else if (iface == LWP_IFACE_LW_FRAME && opcode == LWP_LW_FRAME_REQUEST_OPCODE) {
            g_frame_serial = get_u32(body, 4);
        } else if (iface == LWP_IFACE_LW_TEST && opcode == LWP_LW_TEST_REQUEST_CAPTURE_OPCODE) {
            unsigned int off = (unsigned int)body[4] | ((unsigned int)body[5] << 8);
            unsigned int sl = (unsigned int)body[6] | ((unsigned int)body[7] << 8);
            if (sl >= sizeof g_capture_path) sl = sizeof g_capture_path - 1;
            if (off + sl <= len) {
                memcpy(g_capture_path, body + off, sl);
                g_capture_path[sl] = '\0';
                g_capture_pending = 1;
            }
        } else if (iface == LWP_IFACE_LW_WINDOW &&
                   opcode == LWP_LW_WINDOW_SET_TITLE_BUTTONS_OPCODE && len >= 28) {
            /* 引擎请求的三键配置（visible 位掩码/side/margin/spacing/size/colorMode） */
            for (int i = 0; i < 6; i++) {
                g_title_buttons_cfg[i] = get_u32(body, 4 + i * 4);
            }
            g_title_buttons_pending = 1;
            LOGI_LWP("title buttons cfg requested visible=0x%x margin=%u spacing=%u size=%u mode=%u",
                     g_title_buttons_cfg[0], g_title_buttons_cfg[2], g_title_buttons_cfg[3],
                     g_title_buttons_cfg[4], g_title_buttons_cfg[5]);
        } else if (iface == LWP_IFACE_LW_WINDOW && opcode == LWP_LW_WINDOW_SET_STATE_OPCODE) {
            g_window_state = get_u32(body, 4);
        } else if (iface == LWP_IFACE_LW_WINDOW && opcode == LWP_LW_WINDOW_CLOSE_OPCODE) {
            g_close_requested = 1;
        } else if (iface == LWP_IFACE_LW_APP && opcode == LWP_LW_APP_EXIT_OPCODE) {
            g_exit_code = (int)get_u32(body, 4);
        } else if (iface == LWP_IFACE_LW_DIALOG &&
                   (opcode == LWP_LW_DIALOG_OPEN_FILE_OPCODE || opcode == LWP_LW_DIALOG_SAVE_FILE_OPCODE)) {
            g_dialog_pending = (opcode == LWP_LW_DIALOG_SAVE_FILE_OPCODE) ? 2 : 1;
            g_dialog_serial = get_u32(body, 4);
            unsigned int off = (unsigned int)body[8] | ((unsigned int)body[9] << 8);
            unsigned int sl = (unsigned int)body[10] | ((unsigned int)body[11] << 8);
            if (sl >= sizeof g_dialog_suggested) sl = sizeof g_dialog_suggested - 1;
            if (off + sl <= len) {
                memcpy(g_dialog_suggested, body + off, sl);
                g_dialog_suggested[sl] = '\0';
            }
        } else if (iface == LWP_IFACE_LW_WINDOW &&
                   opcode == LWP_LW_WINDOW_SET_TITLE_OPCODE) {
            unsigned int off = (unsigned int)body[4] | ((unsigned int)body[5] << 8);
            unsigned int sl = (unsigned int)body[6] | ((unsigned int)body[7] << 8);
            if (off + sl <= len && sl < sizeof(g_pending_title)) {
                memcpy(g_pending_title, body + off, sl);
                g_pending_title[sl] = 0;
                g_pending_title_flag = 1;
            }
        } else if (iface == LWP_IFACE_LW_WINDOW &&
                   opcode == LWP_LW_WINDOW_SET_MIN_MAX_OPCODE && len >= 20) {
            g_limits[0] = (int)get_u32(body, 4);
            g_limits[1] = (int)get_u32(body, 8);
            g_limits[2] = (int)get_u32(body, 12);
            g_limits[3] = (int)get_u32(body, 16);
            g_pending_limits_flag = 1;
        } else if (iface == LWP_IFACE_LW_WINDOW &&
                   opcode == LWP_LW_WINDOW_BEGIN_MOVE_OPCODE) {
            /* 纯移动没有等价 API（系统窗口管理器负责）；缩放走 begin_resize -> resize 会话。 */
            LOGI_LWP("window begin_move ignored on OHOS");
        } else if (iface == LWP_IFACE_LW_WINDOW &&
                   opcode == LWP_LW_WINDOW_BEGIN_RESIZE_OPCODE) {
            g_resize_edges = (int)get_u32(body, 4);
            g_resize_anchor_x = -1;
            g_resize_anchor_y = -1;
            g_resize_start_w = g_win_w;
            g_resize_start_h = g_win_h;
            LOGI_LWP("begin_resize edges=%d start=%dx%d", g_resize_edges, g_win_w, g_win_h);
        } else if (iface == LWP_IFACE_LW_SEAT && opcode == LWP_LW_SEAT_SET_CURSOR_OPCODE) {
            g_cursor_shape = (int)get_u32(body, 4);
            LOGI_LWP("cursor shape -> %d", g_cursor_shape);
        } else if (iface == LWP_IFACE_LW_TEXT_INPUT &&
                   opcode == LWP_LW_TEXT_INPUT_ENABLE_OPCODE) {
            /* 焦点进入输入框：挂载系统输入法（原生 C API，见 text_input.cpp）。
             * input_type/enter_key 由引擎给定（since=2）；旧引擎发 4 字节体时按默认值。 */
            unsigned int itype = LWP_IME_TEXT_INPUT_TYPE_TEXT;
            unsigned int ekey = LWP_IME_ENTER_KEY_DONE;
            if (len >= 12) {
                itype = get_u32(body, 4);
                ekey = get_u32(body, 8);
            }
            lanlu_ime_enable(g_win_id_for_ime, itype, ekey, g_show_soft_keyboard ? 1 : 0);
            g_ime_want = 1;
        } else if (iface == LWP_IFACE_LW_TEXT_INPUT &&
                   opcode == LWP_LW_TEXT_INPUT_DISABLE_OPCODE) {
            lanlu_ime_disable();
            g_ime_want = 0;
        } else if (iface == LWP_IFACE_LW_TEXT_INPUT &&
                   opcode == LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_OPCODE) {
            g_ime_cursor_x = (int)get_u32(body, 4);
            g_ime_cursor_y = (int)get_u32(body, 8);
            g_ime_cursor_w = (int)get_u32(body, 12);
            g_ime_cursor_h = (int)get_u32(body, 16);
            g_ime_cursor_pending = 1;
            /* 直接通知系统输入法（不经过 ArkTS 轮询）；原点用输入过滤器持续校准的值。 */
            refresh_ime_origin();
            lanlu_ime_set_cursor_rect(g_ime_cursor_x, g_ime_cursor_y, g_ime_cursor_w, g_ime_cursor_h,
                                      g_ime_origin_x, g_ime_origin_y);
            LOGI_LWP("ime cursor rect %d,%d %dx%d", g_ime_cursor_x, g_ime_cursor_y,
                     g_ime_cursor_w, g_ime_cursor_h);
        } else if (iface == LWP_IFACE_LW_SYSTEM && opcode == LWP_LW_SYSTEM_LOG_OPCODE) {
            /* 引擎日志 -> hilog（计划 §16：两通道日志对齐时间线） */
            uint32_t off = (uint32_t)body[5] | ((uint32_t)body[6] << 8);
            uint32_t tl = (uint32_t)body[7] | ((uint32_t)body[8] << 8);
            if (tl >= sizeof g_logbuf) tl = sizeof g_logbuf - 1;
            if (off + tl <= len) {
                memcpy(g_logbuf, body + off, tl);
                g_logbuf[tl] = '\0';
                LOGI_LWP("%s", g_logbuf);
            }
        } else if (iface == LWP_IFACE_LW_CLIPBOARD && opcode == LWP_LW_CLIPBOARD_SET_OPCODE) {
            /* clipboard.set(mime, text)：两个字符串都从 body 里取，mime 忽略（恒 text/plain） */
            unsigned int moff = (unsigned int)body[4] | ((unsigned int)body[5] << 8);
            unsigned int mlen = (unsigned int)body[6] | ((unsigned int)body[7] << 8);
            unsigned int toff = (unsigned int)body[8] | ((unsigned int)body[9] << 8);
            unsigned int tlen = (unsigned int)body[10] | ((unsigned int)body[11] << 8);
            (void)moff;
            (void)mlen;
            if (tlen >= sizeof g_clip_set) tlen = sizeof g_clip_set - 1;
            if (toff + tlen <= len) {
                memcpy(g_clip_set, body + toff, tlen);
                g_clip_set[tlen] = '\0';
                g_clip_set_pending = 1;
            }
        } else if (iface == LWP_IFACE_LW_CLIPBOARD && opcode == LWP_LW_CLIPBOARD_GET_OPCODE) {
            g_clip_get_serial = get_u32(body, 4);   /* ArkTS 读完系统剪贴板后回 clipboard.text */
        }
    }
    return n;
}

/* 一次性取走待回执的 frame.request serial（0 = 无）。
 * 注意：泵里**已有**一个 `g_frame_serial` 分支（第 264 行附近），别再插第二个分支——
 * if/else-if 链里后面的同名分支永远不执行（第 70 轮为此白跑了两轮构建）。 */
/* 一次性取走待应用的光标形状；返回 -1 表示没有新值 */
int lanlu_lwp_take_cursor_shape(void) {
    int v = g_cursor_shape;
    g_cursor_shape = -1;
    return v;
}

/* 一次性取走待应用的 IME 光标矩形；返回 1 表示有新值 */
int lanlu_lwp_take_ime_cursor_rect(int* x, int* y, int* w, int* h) {
    if (!g_ime_cursor_pending) return 0;
    g_ime_cursor_pending = 0;
    if (x) *x = g_ime_cursor_x;
    if (y) *y = g_ime_cursor_y;
    if (w) *w = g_ime_cursor_w;
    if (h) *h = g_ime_cursor_h;
    return 1;
}

unsigned int lanlu_lwp_take_frame_request(void) {
    unsigned int v = g_frame_serial;
    g_frame_serial = 0;
    return v;
}

unsigned int lanlu_lwp_take_capture_request(void) {
    unsigned int v = g_capture_pending;
    g_capture_pending = 0;
    return v;
}
const char* lanlu_lwp_capture_path(void) { return g_capture_path; }

/* 一次性取走「引擎要求写入系统剪贴板」的文本（返回长度，0 = 无） */
unsigned int lanlu_lwp_take_clip_set(char* out, unsigned int cap) {
    if (!g_clip_set_pending || out == nullptr || cap == 0) return 0;
    unsigned int n = (unsigned int)strlen(g_clip_set);
    if (n >= cap) n = cap - 1;
    memcpy(out, g_clip_set, n);
    out[n] = '\0';
    g_clip_set_pending = 0;
    return n;
}

/* 一次性取走「引擎请求读系统剪贴板」的 serial（0 = 无） */
unsigned int lanlu_lwp_take_clip_get(void) {
    unsigned int v = g_clip_get_serial;
    g_clip_get_serial = 0;
    return v;
}

unsigned int lanlu_lwp_window_state(void) { return g_window_state; }

/* 一次性取走「引擎请求的三键配置」，返回 1 表示有；out 为 6 个 uint 的数组。 */
int lanlu_lwp_take_title_buttons(unsigned int* out) {
    if (!g_title_buttons_pending || out == nullptr) return 0;
    for (int i = 0; i < 6; i++) out[i] = g_title_buttons_cfg[i];
    g_title_buttons_pending = 0;
    return 1;
}

/* 一次性读取并清空：窗口状态是「请求」而非「持续状态」，
 * 不清空会导致 ArkTS 每帧重复执行 maximize/restore（真机上会把窗口压死）。 */
unsigned int lanlu_lwp_take_window_state(void) {
    unsigned int v = g_window_state;
    g_window_state = 0;
    return v;
}
unsigned int lanlu_lwp_take_close_request(void) {
    unsigned int v = g_close_requested;
    g_close_requested = 0;
    return v;
}
int lanlu_lwp_take_exit_code(void) {
    int v = g_exit_code;
    g_exit_code = -1;
    return v;
}

unsigned int lanlu_lwp_dialog_request(void) { return g_dialog_pending; }
unsigned int lanlu_lwp_dialog_serial(void) { return g_dialog_serial; }
const char* lanlu_lwp_dialog_suggested(void) { return g_dialog_suggested; }
void lanlu_lwp_dialog_clear(void) { g_dialog_pending = 0; }

int lanlu_lwp_send_clipboard_text(unsigned int serial, const char* mime, const char* text) {
    if (mime == nullptr) mime = "text/plain";
    if (text == nullptr) text = "";
    size_t mlen = strlen(mime), tlen = strlen(text);
    if (mlen > 100) mlen = 100;
    if (tlen > 200) tlen = 200;
    uint8_t buf[LWP_LW_CLIPBOARD_TEXT_SIZE + 300];
    memset(buf, 0, sizeof buf);
    uint32_t total = (uint32_t)(LWP_LW_CLIPBOARD_TEXT_SIZE + mlen + tlen);
    put_u32(buf, 0, total);
    put_u32(buf, 4, serial);
    uint16_t moff = LWP_LW_CLIPBOARD_TEXT_SIZE, mlen16 = (uint16_t)mlen;
    uint16_t toff = (uint16_t)(moff + mlen), tlen16 = (uint16_t)tlen;
    memcpy(buf + 8, &moff, 2);  memcpy(buf + 10, &mlen16, 2);
    memcpy(buf + 12, &toff, 2); memcpy(buf + 14, &tlen16, 2);
    memcpy(buf + moff, mime, mlen);
    memcpy(buf + toff, text, tlen);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_CLIPBOARD,
                              LWP_LW_CLIPBOARD_TEXT_OPCODE, 0, buf, total);
}

int lanlu_lwp_send_dialog_result(unsigned int serial, const char* path) {
    if (path == nullptr) path = "";
    size_t n = strlen(path);
    if (n > 200) n = 200;
    uint8_t buf[LWP_LW_DIALOG_RESULT_SIZE + 200];
    memset(buf, 0, sizeof buf);
    uint32_t total = (uint32_t)(LWP_LW_DIALOG_RESULT_SIZE + n);
    put_u32(buf, 0, total);
    put_u32(buf, 4, serial);
    uint16_t off = LWP_LW_DIALOG_RESULT_SIZE, len = (uint16_t)n;
    memcpy(buf + 8, &off, 2);
    memcpy(buf + 10, &len, 2);
    memcpy(buf + LWP_LW_DIALOG_RESULT_SIZE, path, n);
    return lanlu_lwp_send_raw(LWP_SHELL_EVENT, LWP_IFACE_LW_DIALOG, LWP_LW_DIALOG_RESULT_OPCODE,
                              0, buf, total);
}

unsigned int lanlu_lwp_last_ack_serial(void) { return g_ack_serial; }
unsigned int lanlu_lwp_last_frame_request(void) { return g_frame_serial; }
unsigned int lanlu_lwp_has_create_request(void) { return g_create_pending; }
unsigned int lanlu_lwp_requested_width(void) { return g_window_id; }
const char* lanlu_lwp_requested_title(void) { return g_create_title; }
void lanlu_lwp_clear_create_request(void) { g_create_pending = 0; }

}  // extern "C"
