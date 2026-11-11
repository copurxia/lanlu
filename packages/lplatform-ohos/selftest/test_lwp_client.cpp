// 壳侧 LWP 发送端测试（宿主可跑，不需要设备）。
//
// 验证 lwp_client.cpp 组出的字节流能被通道原样取出、字段与 IDL 一致：
//   指针按下/移动/滚轮、IME 文本、键盘。
// 用法：test_lwp_client protocol   （LANLU_LWP=1，期望真的发到通道）
//       test_lwp_client fallback   （未开启：M6 后没有文件桥，发送方返回 0 表示丢弃）
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "lwp.h"
#include "lwp_protocol.h"

extern "C" {
int lanlu_lwp_send_pointer(int action, float x, float y, int key);
int lanlu_lwp_send_text(const char* text);
int lanlu_lwp_send_key(const char* name, int down);
int lanlu_lwp_send_window_created(unsigned int id, float scale, int ssd);
int lanlu_lwp_send_window_configure(unsigned int w, unsigned int h, unsigned int state);
int lanlu_lwp_send_frame_done(unsigned int serial, unsigned long long time_ns);
int lanlu_lwp_send_surface_available(unsigned long long handle, unsigned int w, unsigned int h);
int lanlu_lwp_send_surface_changed(unsigned int w, unsigned int h);
int lanlu_lwp_send_surface_will_destroy(void);
int lanlu_lwp_window_pump(void);
unsigned int lanlu_lwp_last_ack_serial(void);
unsigned int lanlu_lwp_has_create_request(void);
const char* lanlu_lwp_requested_title(void);
unsigned int lanlu_lwp_last_frame_request(void);
}

static int g_fail = 0;
#define OK(cond, msg) do { if (!(cond)) { printf("  [FAIL] %s\n", msg); g_fail++; } \
                           else { printf("  [ok]   %s\n", msg); } } while (0)

static int run_fallback() {
    // M6 第 1 步之后没有文件桥了：LANLU_LWP=0 时输入被**丢弃**，返回 0 即"没发出去"。
    printf("== 未开启 LANLU_LWP：输入通道关闭（返回 0 = 丢弃，无文件桥）\n");
    OK(lanlu_lwp_send_pointer(11, 1.0f, 2.0f, 0) == 0, "指针被丢弃");
    OK(lanlu_lwp_send_text("x") == 0, "文本被丢弃");
    OK(lanlu_lwp_send_key("Enter", 1) == 0, "键盘被丢弃");
    return g_fail;
}

static int run_protocol() {
    printf("== LANLU_LWP=1：走协议通道\n");
    OK(lanlu_lwp_send_pointer(11, 10.5f, 20.5f, 0) == 1, "发送 pointer_button(down)");
    OK(lanlu_lwp_send_pointer(2, 11.5f, 21.5f, 0) == 1, "发送 pointer_motion");
    OK(lanlu_lwp_send_pointer(13, 3.0f, 0.0f, 0) == 1, "发送 pointer_axis(垂直)");
    OK(lanlu_lwp_send_text("hello") == 1, "发送 text_input");
    OK(lanlu_lwp_send_key("Enter", 1) == 1, "发送 key(down)");
    OK(lanlu_lwp_send_pointer(91, 0.0f, 0.0f, 0) == 0, "诊断码不走协议");

    lwp_channel* ch = nullptr;
    OK(lwp_open("lanlu", 256, &ch) == 0 && ch != nullptr, "打开同一通道");

    lwp_header h;
    memset(&h, 0, sizeof h);
    uint8_t body[LWP_INLINE_MAX];
    uint32_t len = 0;

    // 0) 壳侧握手：首次发送前必须先 hello（协议检查器规则）
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 hello");
    OK(h.iface == LWP_IFACE_LW_CORE && h.opcode == LWP_LW_CORE_HELLO_OPCODE, "iface/opcode = core.hello");
    {
        lwp_lw_core_hello hello;
        memcpy(&hello, body, sizeof hello);
        OK(hello.protocol_major == LWP_PROTOCOL_MAJOR, "hello 协议版本");
        OK(hello.shell_name.len == 4 && memcmp(body + hello.shell_name.off, "ohos", 4) == 0, "壳名 = ohos");
        OK(hello.os_name.len == 4, "OS 名长度 4");
        OK(hello.size == LWP_LW_CORE_HELLO_SIZE + 8, "hello 总长 = 头 + 两个名字");
    }

    // 1) pointer_button down
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 1 条");
    OK(h.iface == LWP_IFACE_LW_INPUT && h.opcode == LWP_LW_INPUT_POINTER_BUTTON_OPCODE, "iface/opcode = pointer_button");
    {
        lwp_lw_input_pointer_button b;
        memcpy(&b, body, sizeof b);
        OK(b.size == LWP_LW_INPUT_POINTER_BUTTON_SIZE, "size 字段正确");
        OK(b.x == 10.5f && b.y == 20.5f, "坐标 10.5,20.5");
        OK(b.button == 0 && b.down == 1, "button=0 down=1");
    }
    // 2) pointer_motion（应带 DROPPABLE）
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 2 条");
    OK(h.opcode == LWP_LW_INPUT_POINTER_MOTION_OPCODE, "opcode = pointer_motion");
    OK((h.flags & LWP_F_DROPPABLE) != 0, "移动事件标了 DROPPABLE");
    {
        lwp_lw_input_pointer_motion m;
        memcpy(&m, body, sizeof m);
        OK(m.x == 11.5f && m.y == 21.5f, "坐标 11.5,21.5");
    }
    // 3) pointer_axis：y=0 表示垂直 -> dy=3.0
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 3 条");
    OK(h.opcode == LWP_LW_INPUT_POINTER_AXIS_OPCODE, "opcode = pointer_axis");
    {
        lwp_lw_input_pointer_axis a;
        memcpy(&a, body, sizeof a);
        OK(a.dx == 0.0f && a.dy == 3.0f, "垂直滚动 -> dy=3");
    }
    // 4) text_input
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 4 条");
    OK(h.opcode == LWP_LW_INPUT_TEXT_INPUT_OPCODE, "opcode = text_input");
    {
        lwp_lw_input_text_input t;
        memcpy(&t, body, sizeof t);
        OK(t.text.off == LWP_LW_INPUT_TEXT_INPUT_SIZE && t.text.len == 5, "文本偏移/长度正确");
        OK(memcmp(body + t.text.off, "hello", 5) == 0, "文本内容 = hello");
    }
    // 5) key
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 5 条");
    OK(h.opcode == LWP_LW_INPUT_KEY_OPCODE, "opcode = key");
    {
        lwp_lw_input_key k;
        memcpy(&k, body, sizeof k);
        OK(k.keycode == 28 && k.down == 1, "Enter -> evdev 28, down");
    }
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == LWP_EAGAIN, "没有多余消息");

    // ── 窗口/帧（壳侧发送端）──────────────────────────────────────────────
    printf("== 窗口与帧\n");
    OK(lanlu_lwp_send_window_created(7, 2.5f, 1) == 1, "发送 window.created");
    OK(lanlu_lwp_send_window_configure(1600, 1200, 1) == 1, "发送 window.configure");
    OK(lanlu_lwp_send_frame_done(9, 42ULL) == 1, "发送 frame.done");

    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 created");
    OK(h.opcode == LWP_LW_WINDOW_CREATED_OPCODE, "opcode = window.created");
    {
        lwp_lw_window_created c2;
        memcpy(&c2, body, sizeof c2);
        OK(c2.window_id == 7 && c2.scale == 2.5f && c2.server_side_decorations == 1, "id/scale/ssd 正确");
    }
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 configure");
    {
        lwp_lw_window_configure cf;
        memcpy(&cf, body, sizeof cf);
        OK(cf.width == 1600 && cf.height == 1200 && cf.state == 1, "尺寸/状态正确");
    }
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 frame.done");
    {
        lwp_lw_frame_done fd;
        memcpy(&fd, body, sizeof fd);
        OK(fd.serial == 9 && fd.time_ns == 42ULL, "serial/time 正确");
    }

    // ── Surface 生命周期（§7.1）──────────────────────────────────────────
    printf("== Surface 生命周期\n");
    OK(lanlu_lwp_send_surface_available(0x1122334455667788ULL, 1600, 1200) == 1, "发送 surface.available");
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 available");
    OK(h.iface == LWP_IFACE_LW_SURFACE && h.opcode == LWP_LW_SURFACE_AVAILABLE_OPCODE, "opcode = surface.available");
    {
        lwp_lw_surface_available sa;
        memcpy(&sa, body, sizeof sa);
        OK(sa.handle == 0x1122334455667788ULL && sa.width == 1600 && sa.height == 1200, "句柄与尺寸正确");
    }
    OK(lanlu_lwp_send_surface_will_destroy() == 1, "发送 surface.will_destroy");
    OK(lwp_recv(ch, LWP_EVENT, &h, body, sizeof body, &len) == 0, "收到 will_destroy");
    OK(h.opcode == LWP_LW_SURFACE_WILL_DESTROY_OPCODE, "opcode = surface.will_destroy");

    // ── 泵：引擎请求 -> ArkTS 可读状态 ────────────────────────────────────
    printf("== 请求泵\n");
    {
        // 模拟引擎发 window.create + ack_configure + frame.request（REQUEST 方向）
        uint8_t cb[32];
        memset(cb, 0, sizeof cb);
        // window.create: size(4) title(4 @4: off=8,len=2) "hi" @8, w @10, h @14, flags @18
        uint32_t total = 8 + 2 + 12;
        memcpy(cb, &total, 4);
        uint16_t off = 8, tl = 2;
        memcpy(cb + 4, &off, 2);
        memcpy(cb + 6, &tl, 2);
        cb[8] = 'h'; cb[9] = 'i';
        uint32_t w = 640, hh = 480, fl = 1;
        memcpy(cb + 10, &w, 4);
        memcpy(cb + 14, &hh, 4);
        memcpy(cb + 18, &fl, 4);
        lwp_send_parts(ch, LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CREATE_OPCODE, 0, cb, total);

        uint8_t ab[8];
        uint32_t ackSize = 8, ackSerial = 33;
        memcpy(ab, &ackSize, 4);
        memcpy(ab + 4, &ackSerial, 4);
        lwp_send_parts(ch, LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE, 0, ab, 8);

        uint8_t fb[8];
        uint32_t fSize = 8, fSerial = 77;
        memcpy(fb, &fSize, 4);
        memcpy(fb + 4, &fSerial, 4);
        lwp_send_parts(ch, LWP_REQUEST, LWP_IFACE_LW_FRAME, LWP_LW_FRAME_REQUEST_OPCODE, 0, fb, 8);

        OK(lanlu_lwp_window_pump() == 3, "泵处理 3 条请求");
        OK(lanlu_lwp_has_create_request() == 1, "记录到 window.create");
        OK(strcmp(lanlu_lwp_requested_title(), "hi") == 0, "标题解析正确");
        OK(lanlu_lwp_last_ack_serial() == 33, "ack serial 记录正确");
        OK(lanlu_lwp_last_frame_request() == 77, "frame.request serial 记录正确");
    }
    return g_fail;
}

int main(int argc, char** argv) {
    const char* mode = argc > 1 ? argv[1] : "protocol";
    int rc;
    if (strcmp(mode, "fallback") == 0) {
        // M6 后 LWP 默认开启：回退模式必须显式 LANLU_LWP=0（unset 等于开启）
        setenv("LANLU_LWP", "0", 1);
        rc = run_fallback();
    } else {
        setenv("LANLU_LWP", "1", 1);
        rc = run_protocol();
    }
    printf("\n%s\n", rc == 0 ? "[PASS] 壳侧 LWP 发送端" : "[FAIL] 壳侧 LWP 发送端");
    return rc == 0 ? 0 : 1;
}
