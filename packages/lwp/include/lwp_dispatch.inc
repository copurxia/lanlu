/* 由 tools/lwp-gen.py 生成，勿手改。
 * 壳端分发桩：switch (iface, opcode)。未实现的消息保留 TODO，编译期可见。 */

static int lwp_dispatch(lwp_channel* ch, const lwp_header* hdr, const void* body) {
    switch (hdr->iface) {
    case LWP_IFACE_LW_CORE:
        switch (hdr->opcode) {
        case LWP_LW_CORE_HELLO_ACK_OPCODE: /* 引擎 -> 壳：确认握手。收到它之前壳不得发送其他消息；它是链路可用的唯一判据（见 docs/l-layer.md M0-4）。 */
            return lwp_handle_lw_core_hello_ack(ch, body);
        case LWP_LW_CORE_PING_OPCODE: /* 引擎 -> 壳：存活探测，壳回 pong（同一 seq）。 */
            return lwp_handle_lw_core_ping(ch, body);
        case LWP_LW_CORE_HELLO_OPCODE: /* 壳 -> 引擎：协议版本、壳身份、OS API 级别、能力位。 */
            return lwp_handle_lw_core_hello(ch, body);
        case LWP_LW_CORE_ERROR_OPCODE: /* 壳 -> 引擎：协议层错误（解码失败、未知 opcode、版本不兼容等）。 */
            return lwp_handle_lw_core_error(ch, body);
        case LWP_LW_CORE_LOG_OPCODE: /* 壳 -> 引擎：统一日志（取代 hilog 丢失与散落的探针文件）。 */
            return lwp_handle_lw_core_log(ch, body);
        case LWP_LW_CORE_PONG_OPCODE: /* 壳 -> 引擎：ping 的回复。 */
            return lwp_handle_lw_core_pong(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_INPUT:
        switch (hdr->opcode) {
        case LWP_LW_INPUT_POINTER_MOTION_OPCODE: /* 指针移动。x/y 为 surface 逻辑坐标（物理像素 / 缩放比）。 */
            return lwp_handle_lw_input_pointer_motion(ch, body);
        case LWP_LW_INPUT_POINTER_BUTTON_OPCODE: /* 按键按下/释放。button 取值对齐 winit：0=左 1=右 2=中。 */
            return lwp_handle_lw_input_pointer_button(ch, body);
        case LWP_LW_INPUT_POINTER_AXIS_OPCODE: /* 滚轮/触摸板滚动。dx/dy 为逻辑行数；wayland 轴向取反后传入（计划 §6.3）。 */
            return lwp_handle_lw_input_pointer_axis(ch, body);
        case LWP_LW_INPUT_KEY_OPCODE: /* 键盘原始事件。keycode 为壳侧单表键码（计划 §6.1：Linux xkb+OHOS 统一映射）；down 区分按下/释放。 */
            return lwp_handle_lw_input_key(ch, body);
        case LWP_LW_INPUT_TEXT_INPUT_OPCODE: /* IME 提交的文本（对应 wayland text-input-v3 commit）。 */
            return lwp_handle_lw_input_text_input(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_SEAT:
        switch (hdr->opcode) {
        case LWP_LW_SEAT_SET_CURSOR_OPCODE: /* 引擎 -> 壳：设置光标形状（对应 wl_pointer.set_cursor 的形状子集）。 */
            return lwp_handle_lw_seat_set_cursor(ch, body);
        case LWP_LW_SEAT_LOCK_CURSOR_OPCODE: /* 引擎 -> 壳：锁定光标到窗口内（游戏/拖拽用）。 */
            return lwp_handle_lw_seat_lock_cursor(ch, body);
        case LWP_LW_SEAT_CAPABILITIES_OPCODE: /* 壳 -> 引擎：设备能力（键盘/指针/触摸/软键盘），位定义见 core_capabilities。 */
            return lwp_handle_lw_seat_capabilities(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_TEXT_INPUT:
        switch (hdr->opcode) {
        case LWP_LW_TEXT_INPUT_ENABLE_OPCODE: /* 引擎 -> 壳：开启输入法（获得焦点时）。 */
            return lwp_handle_lw_text_input_enable(ch, body);
        case LWP_LW_TEXT_INPUT_DISABLE_OPCODE: /* 引擎 -> 壳：关闭输入法。 */
            return lwp_handle_lw_text_input_disable(ch, body);
        case LWP_LW_TEXT_INPUT_SET_SURROUNDING_OPCODE: /* 引擎 -> 壳：告知光标周围文本，便于输入法做联想（text-input-v3 set_surrounding_text）。 */
            return lwp_handle_lw_text_input_set_surrounding(ch, body);
        case LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_OPCODE: /* 引擎 -> 壳：光标矩形（窗口坐标），输入法据此定位候选框。 */
            return lwp_handle_lw_text_input_set_cursor_rect(ch, body);
        case LWP_LW_TEXT_INPUT_PREEDIT_OPCODE: /* 壳 -> 引擎：候选/preedit 文本与光标位置（用于在窗口内自绘候选条）。 */
            return lwp_handle_lw_text_input_preedit(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_CLIPBOARD:
        switch (hdr->opcode) {
        case LWP_LW_CLIPBOARD_GET_OPCODE: /* 引擎 -> 壳：读剪贴板（异步，结果走 event text）。 */
            return lwp_handle_lw_clipboard_get(ch, body);
        case LWP_LW_CLIPBOARD_SET_OPCODE: /* 引擎 -> 壳：写剪贴板。 */
            return lwp_handle_lw_clipboard_set(ch, body);
        case LWP_LW_CLIPBOARD_TEXT_OPCODE: /* 壳 -> 引擎：剪贴板文本（对应 get 的 serial）。 */
            return lwp_handle_lw_clipboard_text(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_DIALOG:
        switch (hdr->opcode) {
        case LWP_LW_DIALOG_OPEN_FILE_OPCODE: /* 引擎 -> 壳：打开文件选择器。结果走 event result。 */
            return lwp_handle_lw_dialog_open_file(ch, body);
        case LWP_LW_DIALOG_SAVE_FILE_OPCODE: /* 引擎 -> 壳：保存对话框。 */
            return lwp_handle_lw_dialog_save_file(ch, body);
        case LWP_LW_DIALOG_RESULT_OPCODE: /* 壳 -> 引擎：选择结果；path 为空表示取消。 */
            return lwp_handle_lw_dialog_result(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_SYSTEM:
        switch (hdr->opcode) {
        case LWP_LW_SYSTEM_LOG_OPCODE: /* 引擎 -> 壳：把日志交给壳输出（hilog），不再各写各的文件。 */
            return lwp_handle_lw_system_log(ch, body);
        case LWP_LW_SYSTEM_INFO_OPCODE: /* 壳 -> 引擎：启动时同步一次的系统信息。 */
            return lwp_handle_lw_system_info(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_TEST:
        switch (hdr->opcode) {
        case LWP_LW_TEST_READY_OPCODE: /* 引擎 -> 壳：引擎启动完成，可以注入测试动作。 */
            return lwp_handle_lw_test_ready(ch, body);
        case LWP_LW_TEST_REQUEST_CAPTURE_OPCODE: /* 引擎 -> 壳：请壳抓一帧（ArkTS componentSnapshot）并写到 path。与 event 方向的 capture 相反。 */
            return lwp_handle_lw_test_request_capture(ch, body);
        case LWP_LW_TEST_INJECT_OPCODE: /* 壳 -> 引擎：注入一条输入（通道句柄见 test.capture 的前置配置）。 */
            return lwp_handle_lw_test_inject(ch, body);
        case LWP_LW_TEST_REPLAY_OPCODE: /* 壳 -> 引擎：把一份 .lwtrace 录制重放进通道（复现真机问题用，计划 §16.3）。path 在设备沙箱内。 */
            return lwp_handle_lw_test_replay(ch, body);
        case LWP_LW_TEST_CAPTURE_OPCODE: /* 壳 -> 引擎：抓一帧并存到 path（真机无 ADB 时用）。 */
            return lwp_handle_lw_test_capture(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_APP:
        switch (hdr->opcode) {
        case LWP_LW_APP_QUIT_OPCODE: /* 引擎 -> 壳：请求退出应用。 */
            return lwp_handle_lw_app_quit(ch, body);
        case LWP_LW_APP_EXIT_OPCODE: /* 引擎 -> 壳：请求退出应用（TerminateSelf）。 */
            return lwp_handle_lw_app_exit(ch, body);
        case LWP_LW_APP_STARTED_OPCODE: /* 壳 -> 引擎：应用已就绪，可以创建窗口（对应 OHOS onForeground）。 */
            return lwp_handle_lw_app_started(ch, body);
        case LWP_LW_APP_RESUMED_OPCODE: /* 壳 -> 引擎：回到前台（OHOS onForeground / wayland focus）。 */
            return lwp_handle_lw_app_resumed(ch, body);
        case LWP_LW_APP_PAUSED_OPCODE: /* 壳 -> 引擎：进入后台（OHOS onBackground）。引擎应停止渲染但保留状态。 */
            return lwp_handle_lw_app_paused(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_WINDOW:
        switch (hdr->opcode) {
        case LWP_LW_WINDOW_CREATE_OPCODE: /* 引擎 -> 壳：创建窗口。返回 id 通过事件 window.created 回来。 */
            return lwp_handle_lw_window_create(ch, body);
        case LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE: /* 引擎 -> 壳：接受 configure。 */
            return lwp_handle_lw_window_ack_configure(ch, body);
        case LWP_LW_WINDOW_SET_TITLE_OPCODE: /* 引擎 -> 壳：改标题。 */
            return lwp_handle_lw_window_set_title(ch, body);
        case LWP_LW_WINDOW_SET_MIN_MAX_OPCODE: /* 引擎 -> 壳：最小/最大尺寸（0 表示不限）。 */
            return lwp_handle_lw_window_set_min_max(ch, body);
        case LWP_LW_WINDOW_SET_STATE_OPCODE: /* 引擎 -> 壳：请求窗口状态变化（最小化/最大化/还原/全屏）。state 位与 configure 一致。 */
            return lwp_handle_lw_window_set_state(ch, body);
        case LWP_LW_WINDOW_CLOSE_OPCODE: /* 引擎 -> 壳：请求关闭窗口（与 quit 不同：只关窗口，应用可继续）。 */
            return lwp_handle_lw_window_close(ch, body);
        case LWP_LW_WINDOW_BEGIN_MOVE_OPCODE: /* 引擎 -> 壳：开始交互式移动窗口（标题栏按下时）。壳用最近一次输入 serial 发起。 */
            return lwp_handle_lw_window_begin_move(ch, body);
        case LWP_LW_WINDOW_BEGIN_RESIZE_OPCODE: /* 引擎 -> 壳：开始交互式缩放。edges 位：1=上 2=下 4=左 8=右（与 xdg-shell 一致）。 */
            return lwp_handle_lw_window_begin_resize(ch, body);
        case LWP_LW_WINDOW_SET_TITLE_BUTTONS_OPCODE: /* 引擎 -> 壳：配置平台侧三键（可见性/位置/尺寸/明暗）。壳按平台能力 best-effort 应用并 clamp；实际生效矩形以 title_buttons_rect 事件为准，不另设配置回执。 */
            return lwp_handle_lw_window_set_title_buttons(ch, body);
        case LWP_LW_WINDOW_CREATED_OPCODE: /* 壳 -> 引擎：窗口已创建，带壳分配的 id 与初始缩放。 */
            return lwp_handle_lw_window_created(ch, body);
        case LWP_LW_WINDOW_CONFIGURE_OPCODE: /* 壳 -> 引擎：建议尺寸/状态变化。引擎必须回 ack（或 apply），否则壳按超时回退。 */
            return lwp_handle_lw_window_configure(ch, body);
        case LWP_LW_WINDOW_CLOSE_REQUEST_OPCODE: /* 壳 -> 引擎：用户点了关闭（对应 xdg_toplevel.close）。引擎可拒绝并继续运行。 */
            return lwp_handle_lw_window_close_request(ch, body);
        case LWP_LW_WINDOW_FOCUS_OPCODE: /* 壳 -> 引擎：焦点变化。 */
            return lwp_handle_lw_window_focus(ch, body);
        case LWP_LW_WINDOW_DRAG_ENTER_OPCODE: /* 壳 -> 引擎：拖放进入窗口。uris 以 \n 分隔（可能为空，等 drop 时才有）。 */
            return lwp_handle_lw_window_drag_enter(ch, body);
        case LWP_LW_WINDOW_DRAG_MOTION_OPCODE: /* 壳 -> 引擎：拖放在窗口内移动。 */
            return lwp_handle_lw_window_drag_motion(ch, body);
        case LWP_LW_WINDOW_DRAG_LEAVE_OPCODE: /* 壳 -> 引擎：拖放离开窗口（未落下）。 */
            return lwp_handle_lw_window_drag_leave(ch, body);
        case LWP_LW_WINDOW_DROP_OPCODE: /* 壳 -> 引擎：拖放落下。uris 以 \n 分隔（file:// URI 已解码为本地路径）。 */
            return lwp_handle_lw_window_drop(ch, body);
        case LWP_LW_WINDOW_TITLE_BUTTONS_RECT_OPCODE: /* 壳 -> 引擎：平台三键当前矩形（窗口局部**物理 px**，壳已从 vp 换算）+ 可见性。语义对齐 OHOS TitleButtonRect（right/top 是右/上边界）；right==0 表示平台未给出可靠左边界，引擎只按 width/height 做右侧/顶部避让。全屏或三键隐藏时 width=height=0、visible=false。 */
            return lwp_handle_lw_window_title_buttons_rect(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_SURFACE:
        switch (hdr->opcode) {
        case LWP_LW_SURFACE_ATTACH_OPCODE: /* 引擎 -> 壳：提交一帧。buffer 句柄由 lgpu 分配（VkImage/共享内存），这里只传句柄。 */
            return lwp_handle_lw_surface_attach(ch, body);
        case LWP_LW_SURFACE_FRAME_DONE_OPCODE: /* 壳 -> 引擎：上一帧已显示（对应 wl_callback.done），引擎可提交下一帧。 */
            return lwp_handle_lw_surface_frame_done(ch, body);
        case LWP_LW_SURFACE_AVAILABLE_OPCODE: /* 壳 -> 引擎：surface 可用（含 native window 句柄与像素尺寸）。对应 OH_ArkUI_SurfaceCallback_SetSurfaceCreatedEvent。 */
            return lwp_handle_lw_surface_available(ch, body);
        case LWP_LW_SURFACE_CHANGED_OPCODE: /* 壳 -> 引擎：尺寸变化（优先 reconfigure 现有 swapchain，不要销毁重建——Maleoon 第三次重建必崩，见 §7.1）。 */
            return lwp_handle_lw_surface_changed(ch, body);
        case LWP_LW_SURFACE_WILL_DESTROY_OPCODE: /* 壳 -> 引擎：surface 即将销毁。引擎必须**同步**停止渲染并释放 surface（回调返回后旧 window 立即失效）。 */
            return lwp_handle_lw_surface_will_destroy(ch, body);
        case LWP_LW_SURFACE_HIDDEN_OPCODE: /* 壳 -> 引擎：切后台/息屏（只触发 hidden，不触发 destroyed）。引擎停帧但保留 surface。 */
            return lwp_handle_lw_surface_hidden(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_FRAME:
        switch (hdr->opcode) {
        case LWP_LW_FRAME_REQUEST_OPCODE: /* 引擎 -> 壳：请求在下一帧回调我。 */
            return lwp_handle_lw_frame_request(ch, body);
        case LWP_LW_FRAME_DONE_OPCODE: /* 壳 -> 引擎：可以画了（vsync 到达）。 */
            return lwp_handle_lw_frame_done(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    case LWP_IFACE_LW_DISPLAY:
        switch (hdr->opcode) {
        case LWP_LW_DISPLAY_INFO_OPCODE: /* 壳 -> 引擎：显示器参数（含非整数缩放与 inset 安全区）。 */
            return lwp_handle_lw_display_info(ch, body);
        default: return -LWP_ERR_UNKNOWN_OPCODE;
        }
    default: return -LWP_ERR_UNKNOWN_IFACE;
    }
}
