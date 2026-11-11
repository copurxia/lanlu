/* 由 tools/lwp-gen.py 生成，勿手改。
 * 源：packages/lwp/protocol/ 下的 TOML（计划 §5.1、§5.5）
 * 约定：packed、小端；每条消息体首字段 uint32 size（含自身，不含 lwp_header）；
 *       string = { uint16 off; uint16 len; }，off 相对消息体起点。
 */
#ifndef LWP_PROTOCOL_H
#define LWP_PROTOCOL_H

#include <stdint.h>
#include <stddef.h>

#define LWP_PROTOCOL_MAJOR 1
#define LWP_PROTOCOL_MINOR 0

/* 方向 */
#define LWP_DIR_REQUEST 0
#define LWP_DIR_EVENT   1

typedef struct { uint16_t off; uint16_t len; } lwp_str;

/* ---- 接口 lw_core（version 1）---- */
#define LWP_IFACE_LW_CORE 1
#define LWP_IFACE_LW_CORE_VERSION 1

/* 引擎 -> 壳：确认握手。收到它之前壳不得发送其他消息；它是链路可用的唯一判据（见 docs/l-layer.md M0-4）。 */
#define LWP_LW_CORE_HELLO_ACK_OPCODE 0
#define LWP_LW_CORE_HELLO_ACK_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint16_t protocol_major;
    uint16_t protocol_minor;
    uint32_t engine_version;
    lwp_str engine_name;
} lwp_lw_core_hello_ack;

/* 引擎 -> 壳：存活探测，壳回 pong（同一 seq）。 */
#define LWP_LW_CORE_PING_OPCODE 1
#define LWP_LW_CORE_PING_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t seq;
} lwp_lw_core_ping;

/* 壳 -> 引擎：协议版本、壳身份、OS API 级别、能力位。 */
#define LWP_LW_CORE_HELLO_OPCODE 0
#define LWP_LW_CORE_HELLO_SIZE 28
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint16_t protocol_major;
    uint16_t protocol_minor;
    lwp_str shell_name;
    lwp_str os_name;
    uint32_t os_api_level;
    uint64_t capabilities;
} lwp_lw_core_hello;

/* 壳 -> 引擎：协议层错误（解码失败、未知 opcode、版本不兼容等）。 */
#define LWP_LW_CORE_ERROR_OPCODE 1
#define LWP_LW_CORE_ERROR_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    int32_t code;
    lwp_str message;
} lwp_lw_core_error;

/* 壳 -> 引擎：统一日志（取代 hilog 丢失与散落的探针文件）。 */
#define LWP_LW_CORE_LOG_OPCODE 2
#define LWP_LW_CORE_LOG_SIZE 13
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint8_t level;
    lwp_str module;
    lwp_str text;
} lwp_lw_core_log;

/* 壳 -> 引擎：ping 的回复。 */
#define LWP_LW_CORE_PONG_OPCODE 3
#define LWP_LW_CORE_PONG_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t seq;
} lwp_lw_core_pong;

/* ---- 接口 lw_input（version 1）---- */
#define LWP_IFACE_LW_INPUT 2
#define LWP_IFACE_LW_INPUT_VERSION 1

/* 指针移动。x/y 为 surface 逻辑坐标（物理像素 / 缩放比）。 */
#define LWP_LW_INPUT_POINTER_MOTION_OPCODE 0
#define LWP_LW_INPUT_POINTER_MOTION_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    float x;
    float y;
} lwp_lw_input_pointer_motion;

/* 按键按下/释放。button 取值对齐 winit：0=左 1=右 2=中。 */
#define LWP_LW_INPUT_POINTER_BUTTON_OPCODE 1
#define LWP_LW_INPUT_POINTER_BUTTON_SIZE 14
typedef struct __attribute__((packed)) {
    uint32_t size;
    float x;
    float y;
    uint8_t button;
    uint8_t down;
} lwp_lw_input_pointer_button;

/* 滚轮/触摸板滚动。dx/dy 为逻辑行数；wayland 轴向取反后传入（计划 §6.3）。 */
#define LWP_LW_INPUT_POINTER_AXIS_OPCODE 2
#define LWP_LW_INPUT_POINTER_AXIS_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    float dx;
    float dy;
} lwp_lw_input_pointer_axis;

/* 键盘原始事件。keycode 为壳侧单表键码（计划 §6.1：Linux xkb+OHOS 统一映射）；down 区分按下/释放。 */
#define LWP_LW_INPUT_KEY_OPCODE 3
#define LWP_LW_INPUT_KEY_SIZE 9
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t keycode;
    uint8_t down;
} lwp_lw_input_key;

/* IME 提交的文本（对应 wayland text-input-v3 commit）。 */
#define LWP_LW_INPUT_TEXT_INPUT_OPCODE 4
#define LWP_LW_INPUT_TEXT_INPUT_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str text;
} lwp_lw_input_text_input;

/* ---- 接口 lw_seat（version 1）---- */
#define LWP_IFACE_LW_SEAT 8
#define LWP_IFACE_LW_SEAT_VERSION 1

/* 引擎 -> 壳：设置光标形状（对应 wl_pointer.set_cursor 的形状子集）。 */
#define LWP_LW_SEAT_SET_CURSOR_OPCODE 0
#define LWP_LW_SEAT_SET_CURSOR_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t shape;
} lwp_lw_seat_set_cursor;

/* 引擎 -> 壳：锁定光标到窗口内（游戏/拖拽用）。 */
#define LWP_LW_SEAT_LOCK_CURSOR_OPCODE 1
#define LWP_LW_SEAT_LOCK_CURSOR_SIZE 5
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint8_t locked;
} lwp_lw_seat_lock_cursor;

/* 壳 -> 引擎：设备能力（键盘/指针/触摸/软键盘），位定义见 core_capabilities。 */
#define LWP_LW_SEAT_CAPABILITIES_OPCODE 0
#define LWP_LW_SEAT_CAPABILITIES_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint64_t bits;
} lwp_lw_seat_capabilities;

/* ---- 接口 lw_text_input（version 1）---- */
#define LWP_IFACE_LW_TEXT_INPUT 9
#define LWP_IFACE_LW_TEXT_INPUT_VERSION 1

/* 引擎 -> 壳：开启输入法（获得焦点时）。 */
#define LWP_LW_TEXT_INPUT_ENABLE_OPCODE 0
#define LWP_LW_TEXT_INPUT_ENABLE_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_text_input_enable;

/* 引擎 -> 壳：关闭输入法。 */
#define LWP_LW_TEXT_INPUT_DISABLE_OPCODE 1
#define LWP_LW_TEXT_INPUT_DISABLE_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_text_input_disable;

/* 引擎 -> 壳：告知光标周围文本，便于输入法做联想（text-input-v3 set_surrounding_text）。 */
#define LWP_LW_TEXT_INPUT_SET_SURROUNDING_OPCODE 2
#define LWP_LW_TEXT_INPUT_SET_SURROUNDING_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str text;
    uint32_t cursor;
    uint32_t anchor;
} lwp_lw_text_input_set_surrounding;

/* 引擎 -> 壳：光标矩形（窗口坐标），输入法据此定位候选框。 */
#define LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_OPCODE 3
#define LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_SIZE 20
typedef struct __attribute__((packed)) {
    uint32_t size;
    int32_t x;
    int32_t y;
    int32_t w;
    int32_t h;
} lwp_lw_text_input_set_cursor_rect;

/* 壳 -> 引擎：候选/preedit 文本与光标位置（用于在窗口内自绘候选条）。 */
#define LWP_LW_TEXT_INPUT_PREEDIT_OPCODE 0
#define LWP_LW_TEXT_INPUT_PREEDIT_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str text;
    uint32_t cursor;
} lwp_lw_text_input_preedit;

/* ---- 接口 lw_clipboard（version 1）---- */
#define LWP_IFACE_LW_CLIPBOARD 10
#define LWP_IFACE_LW_CLIPBOARD_VERSION 1

/* 引擎 -> 壳：读剪贴板（异步，结果走 event text）。 */
#define LWP_LW_CLIPBOARD_GET_OPCODE 0
#define LWP_LW_CLIPBOARD_GET_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
} lwp_lw_clipboard_get;

/* 引擎 -> 壳：写剪贴板。 */
#define LWP_LW_CLIPBOARD_SET_OPCODE 1
#define LWP_LW_CLIPBOARD_SET_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str mime;
    lwp_str text;
} lwp_lw_clipboard_set;

/* 壳 -> 引擎：剪贴板文本（对应 get 的 serial）。 */
#define LWP_LW_CLIPBOARD_TEXT_OPCODE 0
#define LWP_LW_CLIPBOARD_TEXT_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
    lwp_str mime;
    lwp_str text;
} lwp_lw_clipboard_text;

/* ---- 接口 lw_dialog（version 1）---- */
#define LWP_IFACE_LW_DIALOG 11
#define LWP_IFACE_LW_DIALOG_VERSION 1

/* 引擎 -> 壳：打开文件选择器。结果走 event result。 */
#define LWP_LW_DIALOG_OPEN_FILE_OPCODE 0
#define LWP_LW_DIALOG_OPEN_FILE_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
    lwp_str filters;
} lwp_lw_dialog_open_file;

/* 引擎 -> 壳：保存对话框。 */
#define LWP_LW_DIALOG_SAVE_FILE_OPCODE 1
#define LWP_LW_DIALOG_SAVE_FILE_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
    lwp_str suggested;
} lwp_lw_dialog_save_file;

/* 壳 -> 引擎：选择结果；path 为空表示取消。 */
#define LWP_LW_DIALOG_RESULT_OPCODE 0
#define LWP_LW_DIALOG_RESULT_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
    lwp_str path;
} lwp_lw_dialog_result;

/* ---- 接口 lw_system（version 1）---- */
#define LWP_IFACE_LW_SYSTEM 12
#define LWP_IFACE_LW_SYSTEM_VERSION 1

/* 引擎 -> 壳：把日志交给壳输出（hilog），不再各写各的文件。 */
#define LWP_LW_SYSTEM_LOG_OPCODE 0
#define LWP_LW_SYSTEM_LOG_SIZE 9
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint8_t level;
    lwp_str text;
} lwp_lw_system_log;

/* 壳 -> 引擎：启动时同步一次的系统信息。 */
#define LWP_LW_SYSTEM_INFO_OPCODE 0
#define LWP_LW_SYSTEM_INFO_SIZE 24
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str timezone;
    lwp_str language;
    lwp_str font_dir;
    lwp_str home_dir;
    uint32_t api_level;
} lwp_lw_system_info;

/* ---- 接口 lw_test（version 1）---- */
#define LWP_IFACE_LW_TEST 13
#define LWP_IFACE_LW_TEST_VERSION 1

/* 引擎 -> 壳：引擎启动完成，可以注入测试动作。 */
#define LWP_LW_TEST_READY_OPCODE 0
#define LWP_LW_TEST_READY_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t engine_version;
} lwp_lw_test_ready;

/* 引擎 -> 壳：请壳抓一帧（ArkTS componentSnapshot）并写到 path。与 event 方向的 capture 相反。 */
#define LWP_LW_TEST_REQUEST_CAPTURE_OPCODE 1
#define LWP_LW_TEST_REQUEST_CAPTURE_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str path;
} lwp_lw_test_request_capture;

/* 壳 -> 引擎：注入一条输入（通道句柄见 test.capture 的前置配置）。 */
#define LWP_LW_TEST_INJECT_OPCODE 0
#define LWP_LW_TEST_INJECT_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t kind;
    int32_t a;
    int32_t b;
} lwp_lw_test_inject;

/* 壳 -> 引擎：把一份 .lwtrace 录制重放进通道（复现真机问题用，计划 §16.3）。path 在设备沙箱内。 */
#define LWP_LW_TEST_REPLAY_OPCODE 1
#define LWP_LW_TEST_REPLAY_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str path;
} lwp_lw_test_replay;

/* 壳 -> 引擎：抓一帧并存到 path（真机无 ADB 时用）。 */
#define LWP_LW_TEST_CAPTURE_OPCODE 2
#define LWP_LW_TEST_CAPTURE_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str path;
} lwp_lw_test_capture;

/* ---- 接口 lw_app（version 1）---- */
#define LWP_IFACE_LW_APP 3
#define LWP_IFACE_LW_APP_VERSION 1

/* 引擎 -> 壳：请求退出应用。 */
#define LWP_LW_APP_QUIT_OPCODE 0
#define LWP_LW_APP_QUIT_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    int32_t code;
} lwp_lw_app_quit;

/* 引擎 -> 壳：请求退出应用（TerminateSelf）。 */
#define LWP_LW_APP_EXIT_OPCODE 1
#define LWP_LW_APP_EXIT_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    int32_t code;
} lwp_lw_app_exit;

/* 壳 -> 引擎：应用已就绪，可以创建窗口（对应 OHOS onForeground）。 */
#define LWP_LW_APP_STARTED_OPCODE 0
#define LWP_LW_APP_STARTED_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t app_id;
} lwp_lw_app_started;

/* 壳 -> 引擎：回到前台（OHOS onForeground / wayland focus）。 */
#define LWP_LW_APP_RESUMED_OPCODE 1
#define LWP_LW_APP_RESUMED_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_app_resumed;

/* 壳 -> 引擎：进入后台（OHOS onBackground）。引擎应停止渲染但保留状态。 */
#define LWP_LW_APP_PAUSED_OPCODE 2
#define LWP_LW_APP_PAUSED_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_app_paused;

/* ---- 接口 lw_window（version 1）---- */
#define LWP_IFACE_LW_WINDOW 4
#define LWP_IFACE_LW_WINDOW_VERSION 1

/* 引擎 -> 壳：创建窗口。返回 id 通过事件 window.created 回来。 */
#define LWP_LW_WINDOW_CREATE_OPCODE 0
#define LWP_LW_WINDOW_CREATE_SIZE 20
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str title;
    uint32_t width;
    uint32_t height;
    uint32_t flags;
} lwp_lw_window_create;

/* 引擎 -> 壳：接受 configure。 */
#define LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE 1
#define LWP_LW_WINDOW_ACK_CONFIGURE_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
} lwp_lw_window_ack_configure;

/* 引擎 -> 壳：改标题。 */
#define LWP_LW_WINDOW_SET_TITLE_OPCODE 2
#define LWP_LW_WINDOW_SET_TITLE_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    lwp_str title;
} lwp_lw_window_set_title;

/* 引擎 -> 壳：最小/最大尺寸（0 表示不限）。 */
#define LWP_LW_WINDOW_SET_MIN_MAX_OPCODE 3
#define LWP_LW_WINDOW_SET_MIN_MAX_SIZE 20
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t min_w;
    uint32_t min_h;
    uint32_t max_w;
    uint32_t max_h;
} lwp_lw_window_set_min_max;

/* 引擎 -> 壳：请求窗口状态变化（最小化/最大化/还原/全屏）。state 位与 configure 一致。 */
#define LWP_LW_WINDOW_SET_STATE_OPCODE 4
#define LWP_LW_WINDOW_SET_STATE_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t state;
} lwp_lw_window_set_state;

/* 引擎 -> 壳：请求关闭窗口（与 quit 不同：只关窗口，应用可继续）。 */
#define LWP_LW_WINDOW_CLOSE_OPCODE 5
#define LWP_LW_WINDOW_CLOSE_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_window_close;

/* 引擎 -> 壳：开始交互式移动窗口（标题栏按下时）。壳用最近一次输入 serial 发起。 */
#define LWP_LW_WINDOW_BEGIN_MOVE_OPCODE 6
#define LWP_LW_WINDOW_BEGIN_MOVE_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_window_begin_move;

/* 引擎 -> 壳：开始交互式缩放。edges 位：1=上 2=下 4=左 8=右（与 xdg-shell 一致）。 */
#define LWP_LW_WINDOW_BEGIN_RESIZE_OPCODE 7
#define LWP_LW_WINDOW_BEGIN_RESIZE_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t edges;
} lwp_lw_window_begin_resize;

/* 引擎 -> 壳：配置平台侧三键（可见性/位置/尺寸/明暗）。壳按平台能力 best-effort 应用并 clamp；实际生效矩形以 title_buttons_rect 事件为准，不另设配置回执。 */
#define LWP_LW_WINDOW_SET_TITLE_BUTTONS_OPCODE 8
#define LWP_LW_WINDOW_SET_TITLE_BUTTONS_SIZE 28
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t visible;
    uint32_t side;
    uint32_t close_margin;
    uint32_t spacing;
    uint32_t button_size;
    uint32_t color_mode;
} lwp_lw_window_set_title_buttons;

/* 壳 -> 引擎：窗口已创建，带壳分配的 id 与初始缩放。 */
#define LWP_LW_WINDOW_CREATED_OPCODE 0
#define LWP_LW_WINDOW_CREATED_SIZE 13
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t window_id;
    float scale;
    uint8_t server_side_decorations;
} lwp_lw_window_created;

/* 壳 -> 引擎：建议尺寸/状态变化。引擎必须回 ack（或 apply），否则壳按超时回退。 */
#define LWP_LW_WINDOW_CONFIGURE_OPCODE 1
#define LWP_LW_WINDOW_CONFIGURE_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t width;
    uint32_t height;
    uint32_t state;
} lwp_lw_window_configure;

/* 壳 -> 引擎：用户点了关闭（对应 xdg_toplevel.close）。引擎可拒绝并继续运行。 */
#define LWP_LW_WINDOW_CLOSE_REQUEST_OPCODE 2
#define LWP_LW_WINDOW_CLOSE_REQUEST_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_window_close_request;

/* 壳 -> 引擎：焦点变化。 */
#define LWP_LW_WINDOW_FOCUS_OPCODE 3
#define LWP_LW_WINDOW_FOCUS_SIZE 5
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint8_t focused;
} lwp_lw_window_focus;

/* 壳 -> 引擎：拖放进入窗口。uris 以 \n 分隔（可能为空，等 drop 时才有）。 */
#define LWP_LW_WINDOW_DRAG_ENTER_OPCODE 4
#define LWP_LW_WINDOW_DRAG_ENTER_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t x;
    uint32_t y;
    lwp_str uris;
} lwp_lw_window_drag_enter;

/* 壳 -> 引擎：拖放在窗口内移动。 */
#define LWP_LW_WINDOW_DRAG_MOTION_OPCODE 5
#define LWP_LW_WINDOW_DRAG_MOTION_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t x;
    uint32_t y;
} lwp_lw_window_drag_motion;

/* 壳 -> 引擎：拖放离开窗口（未落下）。 */
#define LWP_LW_WINDOW_DRAG_LEAVE_OPCODE 6
#define LWP_LW_WINDOW_DRAG_LEAVE_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_window_drag_leave;

/* 壳 -> 引擎：拖放落下。uris 以 \n 分隔（file:// URI 已解码为本地路径）。 */
#define LWP_LW_WINDOW_DROP_OPCODE 7
#define LWP_LW_WINDOW_DROP_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t x;
    uint32_t y;
    lwp_str uris;
} lwp_lw_window_drop;

/* 壳 -> 引擎：平台三键当前矩形（窗口局部**物理 px**，壳已从 vp 换算）+ 可见性。语义对齐 OHOS TitleButtonRect（right/top 是右/上边界）；right==0 表示平台未给出可靠左边界，引擎只按 width/height 做右侧/顶部避让。全屏或三键隐藏时 width=height=0、visible=false。 */
#define LWP_LW_WINDOW_TITLE_BUTTONS_RECT_OPCODE 8
#define LWP_LW_WINDOW_TITLE_BUTTONS_RECT_SIZE 21
typedef struct __attribute__((packed)) {
    uint32_t size;
    int32_t right;
    int32_t top;
    uint32_t width;
    uint32_t height;
    uint8_t visible;
} lwp_lw_window_title_buttons_rect;

/* ---- 接口 lw_surface（version 1）---- */
#define LWP_IFACE_LW_SURFACE 5
#define LWP_IFACE_LW_SURFACE_VERSION 1

/* 引擎 -> 壳：提交一帧。buffer 句柄由 lgpu 分配（VkImage/共享内存），这里只传句柄。 */
#define LWP_LW_SURFACE_ATTACH_OPCODE 0
#define LWP_LW_SURFACE_ATTACH_SIZE 24
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint64_t buffer;
    uint32_t width;
    uint32_t height;
    uint32_t serial;
} lwp_lw_surface_attach;

/* 壳 -> 引擎：上一帧已显示（对应 wl_callback.done），引擎可提交下一帧。 */
#define LWP_LW_SURFACE_FRAME_DONE_OPCODE 0
#define LWP_LW_SURFACE_FRAME_DONE_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
    uint64_t time_ns;
} lwp_lw_surface_frame_done;

/* 壳 -> 引擎：surface 可用（含 native window 句柄与像素尺寸）。对应 OH_ArkUI_SurfaceCallback_SetSurfaceCreatedEvent。 */
#define LWP_LW_SURFACE_AVAILABLE_OPCODE 1
#define LWP_LW_SURFACE_AVAILABLE_SIZE 20
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint64_t handle;
    uint32_t width;
    uint32_t height;
} lwp_lw_surface_available;

/* 壳 -> 引擎：尺寸变化（优先 reconfigure 现有 swapchain，不要销毁重建——Maleoon 第三次重建必崩，见 §7.1）。 */
#define LWP_LW_SURFACE_CHANGED_OPCODE 2
#define LWP_LW_SURFACE_CHANGED_SIZE 12
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t width;
    uint32_t height;
} lwp_lw_surface_changed;

/* 壳 -> 引擎：surface 即将销毁。引擎必须**同步**停止渲染并释放 surface（回调返回后旧 window 立即失效）。 */
#define LWP_LW_SURFACE_WILL_DESTROY_OPCODE 3
#define LWP_LW_SURFACE_WILL_DESTROY_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_surface_will_destroy;

/* 壳 -> 引擎：切后台/息屏（只触发 hidden，不触发 destroyed）。引擎停帧但保留 surface。 */
#define LWP_LW_SURFACE_HIDDEN_OPCODE 4
#define LWP_LW_SURFACE_HIDDEN_SIZE 4
typedef struct __attribute__((packed)) {
    uint32_t size;
} lwp_lw_surface_hidden;

/* ---- 接口 lw_frame（version 1）---- */
#define LWP_IFACE_LW_FRAME 6
#define LWP_IFACE_LW_FRAME_VERSION 1

/* 引擎 -> 壳：请求在下一帧回调我。 */
#define LWP_LW_FRAME_REQUEST_OPCODE 0
#define LWP_LW_FRAME_REQUEST_SIZE 8
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
} lwp_lw_frame_request;

/* 壳 -> 引擎：可以画了（vsync 到达）。 */
#define LWP_LW_FRAME_DONE_OPCODE 0
#define LWP_LW_FRAME_DONE_SIZE 16
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t serial;
    uint64_t time_ns;
} lwp_lw_frame_done;

/* ---- 接口 lw_display（version 1）---- */
#define LWP_IFACE_LW_DISPLAY 7
#define LWP_IFACE_LW_DISPLAY_VERSION 1

/* 壳 -> 引擎：显示器参数（含非整数缩放与 inset 安全区）。 */
#define LWP_LW_DISPLAY_INFO_OPCODE 0
#define LWP_LW_DISPLAY_INFO_SIZE 28
typedef struct __attribute__((packed)) {
    uint32_t size;
    uint32_t width;
    uint32_t height;
    float scale;
    uint32_t refresh_mhz;
    uint32_t inset_top;
    uint32_t inset_bottom;
} lwp_lw_display_info;

/* error.code 取值；未列出的值一律按 Unknown 处理。 */
#define LWP_CORE_ERROR_NONE 0u
#define LWP_CORE_ERROR_BAD_MESSAGE 1u
#define LWP_CORE_ERROR_UNKNOWN_OPCODE 2u
#define LWP_CORE_ERROR_VERSION_MISMATCH 3u
#define LWP_CORE_ERROR_NOT_HANDSHAKED 4u
#define LWP_CORE_ERROR_DROPPED 5u

/* hello.capabilities：壳宣告的能力位（计划 §5.3）。缺省全 0 = 什么都不支持。 */
#define LWP_CORE_CAPABILITIES_SERVER_SIDE_DECORATIONS 1u
#define LWP_CORE_CAPABILITIES_WINDOW_MOVE 2u
#define LWP_CORE_CAPABILITIES_WINDOW_RESIZE_EDGES 4u
#define LWP_CORE_CAPABILITIES_MIN_MAX_SIZE 8u
#define LWP_CORE_CAPABILITIES_CURSOR_SHAPES 16u
#define LWP_CORE_CAPABILITIES_CURSOR_LOCK 32u
#define LWP_CORE_CAPABILITIES_IME_PREEDIT 64u
#define LWP_CORE_CAPABILITIES_IME_SURROUNDING_TEXT 128u
#define LWP_CORE_CAPABILITIES_CLIPBOARD_READ_ASYNC 256u
#define LWP_CORE_CAPABILITIES_CLIPBOARD_MIME 512u
#define LWP_CORE_CAPABILITIES_DRAG_DROP 1024u
#define LWP_CORE_CAPABILITIES_FILE_DIALOG_SAVE 2048u
#define LWP_CORE_CAPABILITIES_FILE_DIALOG_FOLDER 4096u
#define LWP_CORE_CAPABILITIES_VSYNC 8192u
#define LWP_CORE_CAPABILITIES_FRACTIONAL_SCALE 16384u
#define LWP_CORE_CAPABILITIES_MULTI_WINDOW 32768u
#define LWP_CORE_CAPABILITIES_SOFT_KEYBOARD 65536u
#define LWP_CORE_CAPABILITIES_TITLE_BUTTONS 131072u

#endif /* LWP_PROTOCOL_H */
