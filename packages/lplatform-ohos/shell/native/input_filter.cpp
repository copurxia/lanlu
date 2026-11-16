// lanlu ohos: window-level input filter -> SDL events.
//
// Why: on this device the XComponent DispatchMouseEvent callback (what SDL3's
// OpenHarmony backend uses) starves for seconds at a time, and its component
// local coordinates plus the ~70px window chrome offset shift hits when it
// does flow (same class of bugs horizon-ohos fixed; see port/hap input.cpp).
//
// Lanes (aligned with horizon-ohos):
//  - mouse move/buttons: OH_NativeWindowManager_RegisterMouseEventFilter,
//    display-physical px minus the calibrated window origin -> SDL motion/
//    button events pushed directly into SDL's event queue.
//  - wheel: the filter's AXIS lane (phone) + the overlay node's NODE_ON_AXIS
//    (2in1 reports wheel only there).
//  - keys: OH_NativeWindowManager_RegisterKeyEventFilter -> SDL key events
//    (consumed while our window is active, unless an IME session owns them).
//
// Origin calibration: the filter gives display coordinates; SDL expects
// window-local. Seeded from the ArkTS window rect (which includes chrome),
// then continuously corrected by XComponent mouse events: screenX - x IS the
// component origin on the display. Both SDL's own backend events and ours
// reach SDL; the engine sees whichever flows, coordinates now agree.
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <multimodalinput/oh_axis_type.h>
#include <multimodalinput/oh_input_manager.h>
#include <window_manager/oh_window_event_filter.h>

// L 层输入事件文件桥（定义在 shell_napi.cpp）
extern "C" int lanlu_push_input(int action, float x, float y, int key);
extern "C" void lanlu_lwp_resize_track(int x, int y);
extern "C" void lanlu_lwp_resize_end(void);

#include <hilog/log.h>
#include <cstdio>
#include <cstdarg>
#include <atomic>
#include <time.h>

static void lanlu_log(const char* fmt, ...) {
    char b[256];
    va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    OH_LOG_INFO(LOG_APP, "%{public}s", b);
}
#define LOGI(...) lanlu_log(__VA_ARGS__)
#define LOGE(...) lanlu_log(__VA_ARGS__)

static std::atomic<double> g_origin_x{0.0};
static std::atomic<double> g_origin_y{0.0};
static std::atomic<bool> g_origin_calibrated{false};
static std::atomic<int32_t> g_filter_window_id{-1};
static std::atomic<int32_t> g_ime_active{0};
/* 组件（XComponent）当前是否持有焦点。ArkUI 把键派发给焦点组件，它的 onKeyEvent 已经
 * 带 unicode 与修饰键走 sendKeyEvent；窗口过滤器只在组件丢焦点时兜底，否则同一个键会到两次。 */
static std::atomic<int32_t> g_component_focused{1};
/* 组件鼠标事件最近一次的时间（ms）。组件事件已带组件内坐标，过滤器这条屏幕坐标的路
 * 在 50ms 内不再投递指针，避免同一动作到两次（两条路的坐标系不同，重复会抖动）。 */
static std::atomic<int64_t> g_component_mouse_ms{0};
extern "C" __attribute__((visibility("default")))
void lanlu_set_component_mouse_recent(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    g_component_mouse_ms.store((int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000,
        std::memory_order_relaxed);
}
static bool component_mouse_active(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    const int64_t now = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
    const int64_t last = g_component_mouse_ms.load(std::memory_order_relaxed);
    return last != 0 && (now - last) < 50;
}

extern "C" {
// Called by sdl_main.c after SDL_Init so pushes land in a live queue.
void lanlu_input_ready(void);
void lanlu_seed_origin(double x, double y);
}

void lanlu_seed_origin(double x, double y) {
    // 窗口装饰已去掉（sysTop=0），窗口矩形原点就是内容区原点。
    // 每次调用都覆盖：ArkTS 在 windowRectChange（拖动/最大化/还原）时重新种入，
    // 之前"只种一次"导致窗口一移动，所有点击整体偏移移动距离（评审 M1）。
    g_origin_x.store(x, std::memory_order_relaxed);
    g_origin_y.store(y, std::memory_order_relaxed);
    g_origin_calibrated.store(true, std::memory_order_relaxed);
}

/* 滚轮去重：过滤器 AXIS 通道最近一次投递的时间（ms）。ArkUI onAxisEvent 通道在
 * 过滤器活跃期间（200ms 内）不再重复投递 —— 两条通道同时到达会让滚动距离翻倍
 * 或（符号不一致时）互相抵消（评审 M3）。 */
static std::atomic<int64_t> g_filter_axis_ms{0};
static int64_t lanlu_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
extern "C" __attribute__((visibility("default")))
int lanlu_filter_axis_recent(void) {
    return (lanlu_now_ms() - g_filter_axis_ms.load(std::memory_order_relaxed)) < 200 ? 1 : 0;
}

/* OHOS 按键号（LEFT=0 MIDDLE=1 RIGHT=2）-> LWP 协议（0=左 1=右 2=中，对齐 winit/Wayland 壳） */
static int lanlu_map_button(int32_t ohos_button) {
    switch (ohos_button) {
        case 1: return 2;   // MIDDLE
        case 2: return 1;   // RIGHT
        default: return 0;  // LEFT / 其它
    }
}

// Continuous calibration: called from the XComponent mouse callback with the
// same event in both coordinate spaces. The difference is the component
// origin on the display; the display mouse filter subtracts it.
static void lanlu_calibrate(double local_x, double local_y, double screen_x, double screen_y) {
    if (screen_x <= 0.0 && screen_y <= 0.0) return;
    const double ox = screen_x - local_x;
    const double oy = screen_y - local_y;
    g_origin_x.store(ox, std::memory_order_relaxed);
    g_origin_y.store(oy, std::memory_order_relaxed);
    g_origin_calibrated.store(true, std::memory_order_relaxed);
}

// OHOS button bitmask (LEFT=1 MIDDLE=2 RIGHT=4)：直接写 L 层事件桥（action 11/12）。
extern "C" __attribute__((visibility("default"))) double lanlu_origin_x(void) {
    return g_origin_x.load(std::memory_order_relaxed);
}
extern "C" __attribute__((visibility("default"))) double lanlu_origin_y(void) {
    return g_origin_y.load(std::memory_order_relaxed);
}
extern "C" __attribute__((visibility("default"))) int lanlu_origin_ok(void) {
    return g_origin_calibrated.load(std::memory_order_relaxed) ? 1 : 0;
}

static void lanlu_push_button(uint64_t ts, uint32_t ohos_button, bool down) {
    (void)ts;
    lanlu_push_input(down ? 11 : 12, 0.0f, 0.0f, (int)ohos_button);
}

// Continuous self-calibration: SDL's own OpenHarmony backend still delivers
// XComponent mouse events (component-local px) through its lane. When one
// arrives right after a filter event with no button change, the two describe
// the same physical position, so display - local IS the origin. We sample
// SDL's current mouse position lazily: origin = filter_display - sdl_local.
static std::atomic<int64_t> g_last_filter_ms{0};
static std::atomic<double> g_last_filter_disp_x{0.0};
static std::atomic<double> g_last_filter_disp_y{0.0};

static void lanlu_self_calibrate(void) {
    // P5：SDL 通道已移除，原点校准只依赖 startFilter 传入的窗口矩形。
}

void lanlu_input_ready(void) {
    // no-op placeholder kept for ABI; calibration runs inline in the filter
}


static bool LanluMouseFilter(Input_MouseEvent* event) {
    // 诊断：记录回调是否被调用以及原始 action 码（前 20 次）
    static int s_mouseHits = 0;
    if (event != nullptr && s_mouseHits < 20) {
        s_mouseHits++;
        lanlu_push_input(91, (float)OH_Input_GetMouseEventAction(event), 0.0f, s_mouseHits);
    }
    // 鼠标：写进输入事件文件桥（action 10=移动, 11=按下, 12=抬起），供 lwindow 读取。
    // 鼠标事件只有显示坐标，这里减去窗口原点（startFilter 传入）得到局部坐标。
    if (event != nullptr) {
        const int32_t action = OH_Input_GetMouseEventAction(event);
        // display - origin = 窗口局部坐标（鼠标没有 window 局部坐标 getter，只能自己换算）
        // 用 double 相减再取值：先把原点截成 int 会丢亚像素（评审 M4）
        const double fx = (double)OH_Input_GetMouseEventDisplayX(event) -
            g_origin_x.load(std::memory_order_relaxed);
        const double fy = (double)OH_Input_GetMouseEventDisplayY(event) -
            g_origin_y.load(std::memory_order_relaxed);
        const int32_t mx = (int32_t)fx;
        const int32_t my = (int32_t)fy;
        int code = 0;
        if (action == MOUSE_ACTION_MOVE) code = 10;
        else if (action == MOUSE_ACTION_BUTTON_DOWN) code = 11;
        else if (action == MOUSE_ACTION_BUTTON_UP) code = 12;
        if (code != 0) {
            // 缩放会话：移动时换算新尺寸，松手时结束（壳侧 begin_resize 开启会话）
            if (code == 10) lanlu_lwp_resize_track(mx, my);
            else if (code == 12) lanlu_lwp_resize_end();
            lanlu_push_input(code, (float)fx, (float)fy,
                             code == 10 ? 0 : lanlu_map_button(OH_Input_GetMouseEventButton(event)));
        }
    }
    if (event == nullptr) return false;
    const int32_t action = OH_Input_GetMouseEventAction(event);

    if (action == MOUSE_ACTION_AXIS_UPDATE) {
        const int32_t axis_type = OH_Input_GetMouseEventAxisType(event);
        const float axis_value = OH_Input_GetMouseEventAxisValue(event);
        // P5：滚轮写 L 层事件桥（action 13；x=刻度，y=0 垂直 / 1 水平）
        // 符号与 ArkUI onAxisEvent 通道一致（horizon 实测两源同号）；之前这里取负，
        // 平板（过滤器通道）与 2in1（ArkUI 通道）滚动方向相反（评审 M3）。
        g_filter_axis_ms.store(lanlu_now_ms(), std::memory_order_relaxed);
        if (axis_type == AXIS_TYPE_SCROLL_VERTICAL) {
            lanlu_push_input(13, axis_value / 45.0f, 0.0f, 0);
        } else if (axis_type == AXIS_TYPE_SCROLL_HORIZONTAL) {
            lanlu_push_input(13, axis_value / 45.0f, 1.0f, 0);
        } else {
            return false;
        }
        return false;
    }

    if (action == MOUSE_ACTION_MOVE || action == MOUSE_ACTION_BUTTON_DOWN ||
        action == MOUSE_ACTION_BUTTON_UP) {
        // 只观察，不投递。
        //
        // 为什么不投递：SDL3 的 OpenHarmony 后端已经在 XComponent 的鼠标回调里发送
        // **组件局部坐标**（SDL_openharmonyevents.c: SDL_SendMouseMotion(..., event.x, event.y)），
        // 而窗口级过滤器拿到的是**屏幕坐标**，必须减去窗口原点才能换算；原点只能从 ArkTS
        // 的 windowRect 种入，那个矩形**包含系统装饰**，减去后整体偏上/偏下一个装饰高度。
        // 两条通道各推一份坐标，引擎最终用哪份取决于事件先后 —— 光标随之偏移。
        // 结论：坐标只由 SDL 的 XComponent 通道提供，这里仅保留观测日志（便于联调核对
        // 屏幕坐标与窗口矩形的偏差，例如装饰高度）。
        const double disp_x = (double)OH_Input_GetMouseEventDisplayX(event);
        const double disp_y = (double)OH_Input_GetMouseEventDisplayY(event);
        static std::atomic<uint64_t> g_move_log{0};
        const uint64_t ln = g_move_log.fetch_add(1) + 1;
        if (ln <= 8 || ln % 200 == 0) {
            LOGI("filter observe act=%d disp=(%.0f,%.0f) btn=%u n=%llu (coords come from SDL XComponent lane)",
                 (int)action, disp_x, disp_y,
                 (unsigned)OH_Input_GetMouseEventButton(event), (unsigned long long)ln);
        }
        return false;
    }
    return false;
}

// Window-level key filter: keys must not depend on component focus (focus is
// dropped on window switches / IME hand-off). Consumed unless an IME session
// is active: the IME owns the keyboard then, and consuming here would break
// pinyin composition.
// 剪贴板：系统只放行"窗口 + Ctrl+V 粘贴路径"的读取（pasteboard_service: IsCtrlVProcess），
// 普通线程读取一律 no permission。因此在这里跟踪 Ctrl 状态，用户按下 Ctrl+V 时
/* M6 第 2 步：剪贴板只走协议（lw_clipboard.set/get）；此处原先把系统剪贴板
 * 预读进 clip_in.txt 的逻辑已删除。 */

extern "C" int lanlu_lwp_send_key(const char* name, int down);
static std::atomic<int32_t> g_ctrl_down{0};

/* OHOS 键码 -> 协议键名（与 lwp_client 的 keycode_from_name 对应表一致）。
 * 只覆盖引擎 UI 真正用到的键；其余键不转发（返回 nullptr）。 */
static const char* lanlu_key_name(int32_t code) {
    switch (code) {
        case KEYCODE_ESCAPE: return "Escape";
        case KEYCODE_DEL: return "Backspace";
        case KEYCODE_TAB: return "Tab";
        case KEYCODE_ENTER: return "Enter";
        case KEYCODE_SPACE: return "Space";
        case KEYCODE_MOVE_HOME: return "Home";
        case KEYCODE_MOVE_END: return "End";
        case KEYCODE_FORWARD_DEL: return "Delete";
        case KEYCODE_DPAD_UP: return "Up";
        case KEYCODE_DPAD_DOWN: return "Down";
        case KEYCODE_DPAD_LEFT: return "Left";
        case KEYCODE_DPAD_RIGHT: return "Right";
        default: return nullptr;
    }
}

/* 键盘过滤器：映射成协议键名后投递（不消费事件，返回 false 让 ArkUI/IME 照常收到）。 */
static bool LanluKeyFilter(Input_KeyEvent* event) {
    if (event == nullptr) return false;
    const int32_t action = OH_Input_GetKeyEventAction(event);
    if (action != KEY_ACTION_DOWN && action != KEY_ACTION_UP) return false;
    const int32_t keyCode = OH_Input_GetKeyEventKeyCode(event);
    if (keyCode == KEYCODE_CTRL_LEFT || keyCode == KEYCODE_CTRL_RIGHT) {
        g_ctrl_down.store(action == KEY_ACTION_DOWN ? 1 : 0, std::memory_order_relaxed);
    }
    if (g_ime_active.load(std::memory_order_relaxed) != 0) return false;
    /* 组件有焦点时键已由 onKeyEvent -> sendKeyEvent 发送（带文本），这里不再重复投递。 */
    if (g_component_focused.load(std::memory_order_relaxed) != 0) return false;
    /* 组件鼠标事件在最近 50ms 内活跃：指针已由组件内坐标那条路发出，这里不再重复 */
    if (component_mouse_active()) return false;
    const char* name = lanlu_key_name(keyCode);
    if (name != nullptr) {
        (void)lanlu_lwp_send_key(name, action == KEY_ACTION_DOWN ? 1 : 0);
    }
    return false;
}

// 触摸过滤器：把窗口局部坐标写进 L 层输入事件文件桥。
// 为什么用原生过滤器：ArkUI 的 onTouch 在 XComponentType.SURFACE 上收不到触摸，
// 而这里能拿到窗口局部坐标（OH_Input_GetTouchEventWindowX/Y）。
static bool LanluTouchFilter(Input_TouchEvent* event) {
    if (event == nullptr) return false;
    static int s_touchHits = 0;
    if (s_touchHits < 20) {
        s_touchHits++;
        lanlu_push_input(92, (float)OH_Input_GetTouchEventAction(event), 0.0f, s_touchHits);
    }
    const int32_t action = OH_Input_GetTouchEventAction(event);
    const int32_t x = OH_Input_GetTouchEventWindowX(event);
    const int32_t y = OH_Input_GetTouchEventWindowY(event);
    const int32_t id = OH_Input_GetTouchEventFingerId(event);
    if (action == TOUCH_ACTION_DOWN || action == TOUCH_ACTION_MOVE || action == TOUCH_ACTION_UP) {
        (void)id;   // 只跟主指；key 字段在协议里是按键号，触摸一律当左键
        lanlu_push_input((int)action, (float)x, (float)y, 0);
    }
    return false;   // 不吞事件
}

extern "C" int lanlu_register_filters(int32_t window_id) {
    if (g_filter_window_id.load(std::memory_order_relaxed) == window_id) return 0;
    const int32_t rc = OH_NativeWindowManager_RegisterMouseEventFilter(window_id, LanluMouseFilter);
    if (rc == 0) {
        g_filter_window_id.store(window_id, std::memory_order_relaxed);
        LOGI("mouse filter registered win=%d", (int)window_id);
    } else {
        LOGE("mouse filter register failed rc=%d", (int)rc);
    }
    const int32_t trc = OH_NativeWindowManager_RegisterTouchEventFilter(window_id, LanluTouchFilter);
    LOGI("touch filter register rc=%d", (int)trc);
    OH_NativeWindowManager_RegisterKeyEventFilter(window_id, LanluKeyFilter);
    // 诊断：把过滤器的注册结果写进事件文件桥（action=90），便于真机核对
    lanlu_push_input(90, (float)rc, (float)trc, (int)window_id);
    return rc;
}



// ── IME 活动门禁（字母重复输入修复，2026-11-13）────────────────────────────
// IME attach 期间物理字母键由 IME 的 insertText 提交；键盘过滤器若继续发键码，
// 同一颗键会经"IME insertText + preedit 上屏"与"过滤器 keycode"两条路径到达引擎，
// 引擎 TextField 每个 TextInput 插一次 —— 真机表现为输入 1 个 s 出现 2~3 个 s。
// 此前 g_ime_active 只有声明和读取、没有任何写入（门禁形同虚设）；这里暴露 setter，
// 由 ArkTS 在 attachIme/detach 时拨动。
extern "C" __attribute__((visibility("default")))
void lanlu_set_component_focused(int focused) {
    g_component_focused.store(focused ? 1 : 0, std::memory_order_relaxed);
}

extern "C" __attribute__((visibility("default")))
void lanlu_set_ime_active(int active) {
    g_ime_active.store(active ? 1 : 0, std::memory_order_relaxed);
    LOGI("ime_active=%d", active ? 1 : 0);
}
