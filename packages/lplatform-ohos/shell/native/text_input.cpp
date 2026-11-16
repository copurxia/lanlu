// lanlu ohos: 输入法（IME）原生桥。
//
// 为什么用原生 C API 而不是 ArkTS 的 inputMethod 控制器（对照 mihong 的
// ui/base/ime/ohos/input_method_ohos.cc）：
//   - ArkTS 控制器只能被动接 insertText，拿不到"输入法放了哪些键没吃"，
//     于是窗口键盘过滤器必须整段停发键码以免重复 —— 数字/符号就这样两头落空；
//   - 原生 TextEditorProxy 是平台的真接口：输入法消费的键由 consumeKeyEvents 拦下，
//     没消费的键正常派发给我们的组件，不会重复也不会丢；
//   - 挂载/卸载跟着输入框焦点（引擎的 lw_text_input.enable/disable），不再启动即挂载。
//
// 事件全部走 LWP（lwp_client.cpp 的 lanlu_lwp_send_*），不经过 ArkTS 轮询。

#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <cstdarg>

#include <inputmethod/inputmethod_controller_capi.h>
#include <inputmethod/inputmethod_attach_options_capi.h>
#include <inputmethod/inputmethod_text_config_capi.h>
#include <inputmethod/inputmethod_text_editor_proxy_capi.h>
#include <inputmethod/inputmethod_cursor_info_capi.h>
#include <inputmethod/inputmethod_inputmethod_proxy_capi.h>
#include <inputmethod/inputmethod_types_capi.h>

#include "lwp_protocol.h"

#ifdef __has_include
#if __has_include(<hilog/log.h>)
#include <hilog/log.h>
#define LANLU_HAVE_HILOG 1
#endif
#endif

#ifdef LANLU_HAVE_HILOG
#define IME_LOG(fmt, ...) OH_LOG_INFO(LOG_APP, "[LANLU-IME] " fmt, ##__VA_ARGS__)
#define IME_ERR(fmt, ...) OH_LOG_ERROR(LOG_APP, "[LANLU-IME] " fmt, ##__VA_ARGS__)
#else
#define IME_LOG(fmt, ...) fprintf(stderr, "[LANLU-IME] " fmt "\n", ##__VA_ARGS__)
#define IME_ERR(fmt, ...) fprintf(stderr, "[LANLU-IME] " fmt "\n", ##__VA_ARGS__)
#endif

// 文件追踪：本构建里 hilog 的 LOG_APP 输出在设备上不可见（hilog -x 收不到本进程的
// OH_LOG_INFO），IME 的位置/挂载问题只能靠落盘取证。$HOME/ime_trace.txt，逐行追加。
static void ime_trace(const char* fmt, ...) {
    static int enabled = -1;
    if (enabled < 0) {
        const char* v = getenv("LANLU_PROBE_LGPU");
        enabled = (v != nullptr && v[0] == '1') ? 1 : 0;
    }
    if (!enabled) return;
    const char* home = getenv("HOME");
    if (home == nullptr) return;
    char path[512];
    snprintf(path, sizeof path, "%s/ime_trace.txt", home);
    FILE* f = fopen(path, "a");
    if (f == nullptr) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

extern "C" {
int lanlu_lwp_send_commit_string(const char* text);
int lanlu_lwp_send_preedit(const char* text, uint32_t cursor);
int lanlu_lwp_send_delete_surrounding(uint32_t before, uint32_t after);
int lanlu_lwp_send_key_text(uint32_t evdev, int down, const char* utf8, uint16_t modifiers);
}

/* evdev 键码（引擎唯一的键码表，与 lwp_client.cpp 的表一致） */
#define EVDEV_ENTER 28
#define EVDEV_LEFT 105
#define EVDEV_RIGHT 106
#define EVDEV_UP 103
#define EVDEV_DOWN 108

// ── UTF-16 -> UTF-8（输入法给的是 char16_t*）───────────────────────────────
// 码点索引 -> UTF-8 字节偏移（超过长度则取末尾）。组合串的光标要的是字节偏移。
static size_t codepoint_to_byte(const char16_t* src, size_t len, int32_t cp_index, size_t fallback) {
    if (src == nullptr || cp_index < 0) return fallback;
    size_t bytes = 0;
    int32_t cp = 0;
    for (size_t i = 0; i < len; i++) {
        const uint32_t c = src[i];
        const bool high = c >= 0xD800 && c <= 0xDBFF && i + 1 < len &&
                          src[i + 1] >= 0xDC00 && src[i + 1] <= 0xDFFF;
        if (cp == cp_index) return bytes;
        if (c < 0x80) bytes += 1;
        else if (c < 0x800) bytes += 2;
        else if (high) { bytes += 4; i++; }
        else bytes += 3;
        cp++;
    }
    return bytes;
}

static size_t utf16_to_utf8(const char16_t* src, size_t len, char* out, size_t cap) {
    if (src == nullptr || out == nullptr || cap == 0) return 0;
    size_t o = 0;
    for (size_t i = 0; i < len; i++) {
        uint32_t cp = src[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < len) {
            const uint32_t low = src[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                i++;
            }
        }
        char tmp[4];
        size_t n = 0;
        if (cp < 0x80) {
            tmp[n++] = (char)cp;
        } else if (cp < 0x800) {
            tmp[n++] = (char)(0xC0 | (cp >> 6));
            tmp[n++] = (char)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            tmp[n++] = (char)(0xE0 | (cp >> 12));
            tmp[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            tmp[n++] = (char)(0x80 | (cp & 0x3F));
        } else {
            tmp[n++] = (char)(0xF0 | (cp >> 18));
            tmp[n++] = (char)(0x80 | ((cp >> 12) & 0x3F));
            tmp[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            tmp[n++] = (char)(0x80 | (cp & 0x3F));
        }
        if (o + n + 1 >= cap) break;
        memcpy(out + o, tmp, n);
        o += n;
    }
    out[o] = '\0';
    return o;
}

// ── 会话状态 ─────────────────────────────────────────────────────────────
static InputMethod_TextEditorProxy* g_proxy = nullptr;
static InputMethod_InputMethodProxy* g_ime_proxy = nullptr;
static InputMethod_AttachOptions* g_options = nullptr;
static int32_t g_window_id = -1;
static uint32_t g_input_type = LWP_IME_TEXT_INPUT_TYPE_TEXT;
static uint32_t g_enter_key = IME_ENTER_KEY_DONE;
static bool g_attached = false;
// 窗口 UI 缩放（物理 = 逻辑 × 密度）。引擎给的光标矩形是**逻辑 vp**，
// CursorInfo 要物理屏幕 px，必须乘这个系数（之前漏乘 → 候选框贴在窗口左上角）。
static double g_ime_density = 1.0;

// ArkTS 每次种原点都会调（窗口移动/每秒自愈），落盘便于与截图比对
extern "C" __attribute__((visibility("default")))
void lanlu_ime_trace_origin(double x, double y) {
    ime_trace("seedOrigin=(%.1f,%.1f)", x, y);
}

extern "C" __attribute__((visibility("default")))
void lanlu_ime_set_density(double density) {
    if (density > 0.0) {
        g_ime_density = density;
        ime_trace("density=%.3f", density);
    }
}

// 供 ArkTS 判断键事件要不要当文本发（输入法挂载时才可能重复）
extern "C" __attribute__((visibility("default"))) int lanlu_ime_is_active(void) {
    return g_attached ? 1 : 0;
}

static void apply_text_config(InputMethod_TextConfig* config) {
    if (config == nullptr) return;
    InputMethod_TextInputType type = IME_TEXT_INPUT_TYPE_TEXT;
    switch (g_input_type) {
        case LWP_IME_TEXT_INPUT_TYPE_NUMBER: type = IME_TEXT_INPUT_TYPE_NUMBER; break;
        case LWP_IME_TEXT_INPUT_TYPE_PHONE: type = IME_TEXT_INPUT_TYPE_PHONE; break;
        case LWP_IME_TEXT_INPUT_TYPE_PASSWORD: type = IME_TEXT_INPUT_TYPE_VISIBLE_PASSWORD; break;
        case LWP_IME_TEXT_INPUT_TYPE_URL: type = IME_TEXT_INPUT_TYPE_URL; break;
        case LWP_IME_TEXT_INPUT_TYPE_EMAIL: type = IME_TEXT_INPUT_TYPE_EMAIL_ADDRESS; break;
        default: type = IME_TEXT_INPUT_TYPE_TEXT; break;
    }
    (void)OH_TextConfig_SetInputType(config, type);
    InputMethod_EnterKeyType ek = IME_ENTER_KEY_DONE;
    switch (g_enter_key) {
        case LWP_IME_ENTER_KEY_NONE: ek = IME_ENTER_KEY_NONE; break;
        case LWP_IME_ENTER_KEY_GO: ek = IME_ENTER_KEY_GO; break;
        case LWP_IME_ENTER_KEY_SEARCH: ek = IME_ENTER_KEY_SEARCH; break;
        case LWP_IME_ENTER_KEY_SEND: ek = IME_ENTER_KEY_SEND; break;
        case LWP_IME_ENTER_KEY_NEXT: ek = IME_ENTER_KEY_NEXT; break;
        case LWP_IME_ENTER_KEY_PREVIOUS: ek = IME_ENTER_KEY_PREVIOUS; break;
        case LWP_IME_ENTER_KEY_NEWLINE: ek = IME_ENTER_KEY_NEWLINE; break;
        default: ek = IME_ENTER_KEY_DONE; break;
    }
    (void)OH_TextConfig_SetEnterKeyType(config, ek);
    if (g_window_id >= 0) {
        (void)OH_TextConfig_SetWindowId(config, g_window_id);
    }
    // 声明支持组合串（preedit）：不声明时输入法只发上屏文本，
    // 输入框里就看不到"拼音打了一半"的候选串（真机实测）。
    (void)OH_TextConfig_SetPreviewTextSupport(config, true);
    // 输入法**消费**它处理的键：这些键不再派发给我们，天然不会与 commit 文本重复；
    // 它不处理的键（PC 上的数字、方向键等）照常派发给组件事件，由组件的 onKeyEvent
    // 带着 unicode 发 lw_input.key。这是修"数字打不出来"的关键开关。
    (void)OH_TextConfig_SetConsumeKeyEvents(config, true);
}

// ── TextEditorProxy 回调 ──────────────────────────────────────────────────
static void OnInsertText(InputMethod_TextEditorProxy*, const char16_t* text, size_t length) {
    if (text == nullptr || length == 0) return;
    char buf[1024];
    const size_t n = utf16_to_utf8(text, length, buf, sizeof buf);
    if (n == 0) return;
    ime_trace("commit '%s' -> %d", buf, lanlu_lwp_send_commit_string(buf));
}

static void OnDeleteBackward(InputMethod_TextEditorProxy*, int32_t length) {
    if (length <= 0) return;
    lanlu_lwp_send_delete_surrounding((uint32_t)length, 0);
}

static void OnDeleteForward(InputMethod_TextEditorProxy*, int32_t length) {
    if (length <= 0) return;
    lanlu_lwp_send_delete_surrounding(0, (uint32_t)length);
}

static void SendKeyTap(uint32_t evdev) {
    lanlu_lwp_send_key_text(evdev, 1, nullptr, 0);
    lanlu_lwp_send_key_text(evdev, 0, nullptr, 0);
}

static void OnSendEnterKey(InputMethod_TextEditorProxy*, InputMethod_EnterKeyType enter_key_type) {
    (void)enter_key_type;   // 具体形态由输入法决定；引擎只认 Enter 键
    SendKeyTap(EVDEV_ENTER);
}

static void OnMoveCursor(InputMethod_TextEditorProxy*, InputMethod_Direction direction) {
    switch (direction) {
        case IME_DIRECTION_LEFT: SendKeyTap(EVDEV_LEFT); break;
        case IME_DIRECTION_RIGHT: SendKeyTap(EVDEV_RIGHT); break;
        case IME_DIRECTION_UP: SendKeyTap(EVDEV_UP); break;
        case IME_DIRECTION_DOWN: SendKeyTap(EVDEV_DOWN); break;
        default: break;
    }
}

static void OnGetTextConfig(InputMethod_TextEditorProxy*, InputMethod_TextConfig* config) {
    apply_text_config(config);
}

// 组合中文本（拼音未上屏部分）：让引擎在输入框里画下划线组合串。
static int32_t OnSetPreviewText(InputMethod_TextEditorProxy*, const char16_t* text, size_t length,
                                int32_t start, int32_t end) {
    (void)start;
    if (text == nullptr || length == 0) {
        lanlu_lwp_send_preedit(nullptr, 0);
        return 0;
    }
    char buf[512];
    const size_t n = utf16_to_utf8(text, length, buf, sizeof buf);
    // start/end 是**码点**索引，协议要字节偏移：按 end 精确换算（拿不到就用末尾）。
    const size_t cursor = codepoint_to_byte(text, length, end, n);
    lanlu_lwp_send_preedit(buf, (uint32_t)(cursor > n ? n : cursor));
    return 0;
}

static void OnFinishPreviewText(InputMethod_TextEditorProxy*) {
    lanlu_lwp_send_preedit(nullptr, 0);
}

// 输入法的"设置选区"（语音/整句替换后常见）。引擎侧没有 set_selection 事件，按空实现登记：
// 系统在 Attach 前会校验这个指针非空（真机报错 handleSetSelectionFunc is nullptr -> invalid parameter）。
static void OnHandleSetSelection(InputMethod_TextEditorProxy*, int32_t start, int32_t end) {
    (void)start;
    (void)end;
}

// 光标左右文本查询（联想/纠错用）：按空文本回答，属于可选能力。
static void OnGetLeftTextOfCursor(InputMethod_TextEditorProxy*, int32_t number, char16_t text[], size_t* length) {
    (void)number;
    if (text != nullptr) text[0] = 0;
    if (length != nullptr) *length = 0;
}

static void OnGetRightTextOfCursor(InputMethod_TextEditorProxy*, int32_t number, char16_t text[], size_t* length) {
    (void)number;
    if (text != nullptr) text[0] = 0;
    if (length != nullptr) *length = 0;
}

static int32_t OnGetTextIndexAtCursor(InputMethod_TextEditorProxy*) {
    return 0;
}

static int32_t OnReceivePrivateCommand(InputMethod_TextEditorProxy*, InputMethod_PrivateCommand**, size_t) {
    return 0;
}

static void OnSendKeyboardStatus(InputMethod_TextEditorProxy*, InputMethod_KeyboardStatus status) {
    IME_LOG("keyboard status=%d", (int)status);
}

static void OnHandleExtendAction(InputMethod_TextEditorProxy*, InputMethod_ExtendAction action) {
    // 全选/剪切/复制/粘贴交给引擎的快捷键路径（Ctrl+A/C/X/V 语义）
    switch (action) {
        case IME_EXTEND_ACTION_SELECT_ALL: lanlu_lwp_send_key_text(30, 1, "a", 0x0040); lanlu_lwp_send_key_text(30, 0, nullptr, 0x0040); break;
        case IME_EXTEND_ACTION_COPY: lanlu_lwp_send_key_text(46, 1, "c", 0x0040); lanlu_lwp_send_key_text(46, 0, nullptr, 0x0040); break;
        case IME_EXTEND_ACTION_CUT: lanlu_lwp_send_key_text(45, 1, "x", 0x0040); lanlu_lwp_send_key_text(45, 0, nullptr, 0x0040); break;
        case IME_EXTEND_ACTION_PASTE: lanlu_lwp_send_key_text(47, 1, "v", 0x0040); lanlu_lwp_send_key_text(47, 0, nullptr, 0x0040); break;
        default: break;
    }
}

static InputMethod_TextEditorProxy* create_proxy(void) {
    InputMethod_TextEditorProxy* p = OH_TextEditorProxy_Create();
    if (p == nullptr) {
        IME_ERR("OH_TextEditorProxy_Create failed");
        return nullptr;
    }
    struct {
        const char* name;
        InputMethod_ErrorCode rc;
    } regs[8];
    size_t n = 0;
    regs[n++] = {"InsertText", OH_TextEditorProxy_SetInsertTextFunc(p, OnInsertText)};
    regs[n++] = {"DeleteBackward", OH_TextEditorProxy_SetDeleteBackwardFunc(p, OnDeleteBackward)};
    regs[n++] = {"DeleteForward", OH_TextEditorProxy_SetDeleteForwardFunc(p, OnDeleteForward)};
    regs[n++] = {"SendEnterKey", OH_TextEditorProxy_SetSendEnterKeyFunc(p, OnSendEnterKey)};
    regs[n++] = {"MoveCursor", OH_TextEditorProxy_SetMoveCursorFunc(p, OnMoveCursor)};
    regs[n++] = {"GetTextConfig", OH_TextEditorProxy_SetGetTextConfigFunc(p, OnGetTextConfig)};
    regs[n++] = {"SetPreviewText", OH_TextEditorProxy_SetSetPreviewTextFunc(p, OnSetPreviewText)};
    regs[n++] = {"FinishTextPreview", OH_TextEditorProxy_SetFinishTextPreviewFunc(p, OnFinishPreviewText)};
    for (size_t i = 0; i < n; i++) {
        if (regs[i].rc != IME_ERR_OK) {
            IME_ERR("%s register failed rc=%d", regs[i].name, (int)regs[i].rc);
        }
    }
    // 以下为系统校验/可选回调：全部登记，避免 Attach 被判 invalid parameter
    struct { const char* name; InputMethod_ErrorCode rc; } extra[6];
    size_t m = 0;
    extra[m++] = {"SendKeyboardStatus", OH_TextEditorProxy_SetSendKeyboardStatusFunc(p, OnSendKeyboardStatus)};
    extra[m++] = {"HandleSetSelection", OH_TextEditorProxy_SetHandleSetSelectionFunc(p, OnHandleSetSelection)};
    extra[m++] = {"HandleExtendAction", OH_TextEditorProxy_SetHandleExtendActionFunc(p, OnHandleExtendAction)};
    extra[m++] = {"GetLeftTextOfCursor", OH_TextEditorProxy_SetGetLeftTextOfCursorFunc(p, OnGetLeftTextOfCursor)};
    extra[m++] = {"GetRightTextOfCursor", OH_TextEditorProxy_SetGetRightTextOfCursorFunc(p, OnGetRightTextOfCursor)};
    extra[m++] = {"GetTextIndexAtCursor", OH_TextEditorProxy_SetGetTextIndexAtCursorFunc(p, OnGetTextIndexAtCursor)};
    for (size_t i = 0; i < m; i++) {
        if (extra[i].rc != IME_ERR_OK) {
            IME_ERR("%s register failed rc=%d", extra[i].name, (int)extra[i].rc);
        }
    }
    (void)OH_TextEditorProxy_SetReceivePrivateCommandFunc(p, OnReceivePrivateCommand);
    return p;
}

// ── 对外（lwp_window.cpp 的泵与 ArkTS 调用）──────────────────────────────
extern "C" __attribute__((visibility("default")))
int lanlu_ime_enable(int32_t window_id, uint32_t input_type, uint32_t enter_key, int show_soft) {
    g_window_id = window_id;
    g_input_type = input_type;
    g_enter_key = enter_key;
    if (g_attached) {
        // 已挂载：只更新配置/软键盘，不重复 attach（重复 attach 会叠加输入法会话）
        if (g_ime_proxy != nullptr) {
            if (show_soft) {
                (void)OH_InputMethodProxy_ShowKeyboard(g_ime_proxy);
            }
        }
        return 0;
    }
    if (g_proxy == nullptr) {
        g_proxy = create_proxy();
        if (g_proxy == nullptr) return -1;
    }
    if (g_options == nullptr) {
        g_options = OH_AttachOptions_Create(show_soft != 0);
        if (g_options == nullptr) {
            IME_ERR("OH_AttachOptions_Create failed");
            return -1;
        }
    }
    const InputMethod_ErrorCode rc =
        OH_InputMethodController_Attach(g_proxy, g_options, &g_ime_proxy);
    if (rc != IME_ERR_OK || g_ime_proxy == nullptr) {
        IME_ERR("attach failed rc=%d", (int)rc);
        return -1;
    }
    g_attached = true;
    IME_LOG("attached win=%d type=%u enter=%u soft=%d", window_id, input_type, enter_key, show_soft);
    ime_trace("attached win=%d type=%u soft=%d", window_id, input_type, show_soft);
    return 0;
}

extern "C" __attribute__((visibility("default")))
int lanlu_ime_disable(void) {
    if (!g_attached) return 0;
    g_attached = false;
    if (g_ime_proxy != nullptr) {
        // 先收软键盘再拆会话，否则手机上键盘会残留（与 Chromium DetachTextInputTask 同序）
        (void)OH_InputMethodProxy_HideKeyboard(g_ime_proxy);
        const InputMethod_ErrorCode rc = OH_InputMethodController_Detach(g_ime_proxy);
        if (rc != IME_ERR_OK) IME_ERR("detach rc=%d", (int)rc);
        g_ime_proxy = nullptr;
    }
    lanlu_lwp_send_preedit(nullptr, 0);
    IME_LOG("detached");
    return 0;
}

// 光标矩形（窗口局部像素）→ 显示坐标后通知输入法，候选框跟着光标走。
extern "C" __attribute__((visibility("default")))
void lanlu_ime_set_cursor_rect(int32_t x, int32_t y, int32_t w, int32_t h, double origin_x, double origin_y) {
    // 逻辑 vp -> 物理 px，再叠加窗口在屏幕上的原点 => 屏幕绝对物理像素
    const double px = (double)x * g_ime_density + origin_x;
    const double py = (double)y * g_ime_density + origin_y;
    const double pw = (double)w * g_ime_density;
    const double ph = (double)h * g_ime_density;
    ime_trace("cursor local=(%d,%d %dx%d) d=%.3f origin=(%.1f,%.1f) -> (%.1f,%.1f %.0fx%.0f)",
              x, y, w, h, g_ime_density, origin_x, origin_y, px, py, pw, ph);
    if (!g_attached || g_ime_proxy == nullptr) return;
    InputMethod_CursorInfo* info = OH_CursorInfo_Create(px, py, pw, ph);
    if (info == nullptr) return;
    const InputMethod_ErrorCode rc = OH_InputMethodProxy_NotifyCursorUpdate(g_ime_proxy, info);
    ime_trace("notify rc=%d", (int)rc);
    if (rc != IME_ERR_OK) IME_ERR("NotifyCursorUpdate rc=%d", (int)rc);
    OH_CursorInfo_Destroy(info);
}

extern "C" __attribute__((visibility("default"))) int lanlu_ime_attached(void) {
    return g_attached ? 1 : 0;
}
