/* LWP 协议布局测试（C 侧）。
 *
 * 目的：保证生成的 C 结构体与 IDL 声明的 packed 布局一致 —— 一旦有人给结构体加了
 * 对齐、或生成器改了偏移规则，这里编译期就会失败。
 *
 * 构建/运行：bash packages/lwp/native/run-tests.sh
 */
#include "../include/lwp_protocol.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define CHECK_SIZE(tag, macro) \
    _Static_assert(sizeof(tag) == macro, #tag " 大小与 " #macro " 不一致")

CHECK_SIZE(lwp_lw_core_hello, LWP_LW_CORE_HELLO_SIZE);
CHECK_SIZE(lwp_lw_core_hello_ack, LWP_LW_CORE_HELLO_ACK_SIZE);
CHECK_SIZE(lwp_lw_core_error, LWP_LW_CORE_ERROR_SIZE);
CHECK_SIZE(lwp_lw_core_log, LWP_LW_CORE_LOG_SIZE);
CHECK_SIZE(lwp_lw_core_ping, LWP_LW_CORE_PING_SIZE);
CHECK_SIZE(lwp_lw_core_pong, LWP_LW_CORE_PONG_SIZE);

/* 首字段必须是 uint32 size（计划 §5.1：接收方按 size 跳过未知消息） */
_Static_assert(offsetof(lwp_lw_core_hello, size) == 0, "size 必须是首字段");
_Static_assert(offsetof(lwp_lw_core_hello, protocol_major) == 4, "字段偏移必须与 IDL 一致");
_Static_assert(offsetof(lwp_lw_core_hello, protocol_minor) == 6, "字段偏移必须与 IDL 一致");
_Static_assert(offsetof(lwp_lw_core_hello, shell_name) == 8, "字段偏移必须与 IDL 一致");
_Static_assert(offsetof(lwp_lw_core_hello, os_name) == 12, "字段偏移必须与 IDL 一致");
_Static_assert(offsetof(lwp_lw_core_hello, os_api_level) == 16, "字段偏移必须与 IDL 一致");
_Static_assert(offsetof(lwp_lw_core_hello, capabilities) == 20, "字段偏移必须与 IDL 一致");

int main(void) {
    /* 组装一条 hello 并核对字节布局：string 用 (off,len) 指向消息体尾部 */
    unsigned char buf[64];
    memset(buf, 0, sizeof buf);
    lwp_lw_core_hello *h = (lwp_lw_core_hello *)buf;
    h->size = LWP_LW_CORE_HELLO_SIZE;
    h->protocol_major = LWP_PROTOCOL_MAJOR;
    h->protocol_minor = LWP_PROTOCOL_MINOR;
    h->os_api_level = 26;
    h->capabilities = LWP_CORE_CAPABILITIES_VSYNC | LWP_CORE_CAPABILITIES_IME_PREEDIT;
    h->shell_name.off = 28;
    h->shell_name.len = 4;
    h->os_name.off = 32;
    h->os_name.len = 4;
    memcpy(buf + 28, "ohos", 4);
    memcpy(buf + 32, "ohos", 4);

    printf("hello 布局：size=%u major=%u minor=%u api=%u caps=%llu shell=%.*s os=%.*s\n",
           h->size, h->protocol_major, h->protocol_minor, h->os_api_level,
           (unsigned long long)h->capabilities,
           h->shell_name.len, buf + h->shell_name.off,
           h->os_name.len, buf + h->os_name.off);

    assert(h->size == 28);
    assert(h->protocol_major == 1);
    assert(buf[0] == 28 && buf[1] == 0 && buf[2] == 0 && buf[3] == 0);  /* 小端 uint32 */
    assert((h->capabilities & LWP_CORE_CAPABILITIES_VSYNC) != 0);

    puts("[PASS] lwp C 布局测试");
    return 0;
}
