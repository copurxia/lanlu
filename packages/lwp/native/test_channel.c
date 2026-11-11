/* liblwp 通道测试（C）。计划 §5.2、§10 M1。
 *
 * 覆盖：
 *   1. 基本收发往返、方向隔离
 *   2. 满队列 → LWP_EAGAIN；可丢弃消息计入 dropped
 *   3. 多生产者并发（4 线程 × 2000 条）不丢不乱序（按 producer 校验 serial 单调）
 *   4. 未知/非法头部 → LWP_EBADMSG 并计入 bad
 *   5. blob 生命周期（put/get/release/reuse、越界句柄）
 *   6. lwp_wait 超时与唤醒
 *   7. lwp_open 同名复用返回同一实例
 */
#define _GNU_SOURCE
#include "../include/lwp.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int g_fail = 0;
#define OK(cond, msg) do { if (!(cond)) { printf("  [FAIL] %s\n", msg); g_fail++; } \
                           else { printf("  [ok]   %s\n", msg); } } while (0)

static lwp_header mk(uint16_t iface, uint16_t opcode, uint32_t flags) {
    lwp_header h;
    memset(&h, 0, sizeof h);
    h.iface = iface;
    h.opcode = opcode;
    h.flags = flags;
    return h;
}

/* 1 + 2 + 4：单线程收发、满队列、坏头部 */
static void test_basic(lwp_channel* ch) {
    printf("== 基本收发\n");
    lwp_header h = mk(7, 3, 0);
    uint8_t body[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    OK(lwp_send(ch, LWP_EVENT, &h, body, sizeof body) == LWP_OK, "send 成功");
    lwp_header out;
    uint8_t got[16];
    uint32_t len = 0;
    OK(lwp_recv(ch, LWP_EVENT, &out, got, sizeof got, &len) == LWP_OK, "recv 成功");
    OK(len == 8 && memcmp(got, body, 8) == 0, "载荷一致");
    OK(out.iface == 7 && out.opcode == 3, "头一致");
    OK(out.serial != 0 && out.size == sizeof(lwp_header) + 8, "serial 自动分配、size 正确");

    /* 方向隔离：EVENT 收到的不会出现在 REQUEST */
    OK(lwp_recv(ch, LWP_REQUEST, &out, got, sizeof got, &len) == LWP_EAGAIN, "方向隔离");

    /* 空队列 */
    OK(lwp_recv(ch, LWP_EVENT, &out, got, sizeof got, &len) == LWP_EAGAIN, "空队列返回 EAGAIN");

    printf("== 非法头部\n");
    /* 正常路径：size 由库重算 */
    lwp_header good = mk(7, 4, 0);
    uint8_t b2[4] = {0, 0, 0, 0};
    OK(lwp_send(ch, LWP_EVENT, &good, b2, 4) == LWP_OK, "发送（头部 size 由库重算）");
    OK(lwp_recv(ch, LWP_EVENT, &out, got, sizeof got, &len) == LWP_OK, "库重算后的 size 合法");
    OK(out.size == sizeof(lwp_header) + 4, "size 被重算为 头部+载荷");

    /* 测试挂钩：直接塞一条 size 小于头部的恶意消息 */
    lwp_stats sb0, sb1;
    lwp_get_stats(ch, &sb0);
    lwp_header bad = mk(7, 5, 0);
    bad.size = 1;
    OK(lwp__test_push_raw(ch, LWP_EVENT, &bad, b2, 0) == LWP_OK, "塞入非法头部消息");
    OK(lwp_recv(ch, LWP_EVENT, &out, got, sizeof got, &len) == LWP_EBADMSG, "接收侧拒绝非法 size");
    lwp_get_stats(ch, &sb1);
    OK(sb1.bad == sb0.bad + 1, "bad 计数 +1");

    /* 超大 size 同样拒绝 */
    bad.size = sizeof(lwp_header) + LWP_INLINE_MAX + 1;
    lwp__test_push_raw(ch, LWP_EVENT, &bad, b2, 0);
    OK(lwp_recv(ch, LWP_EVENT, &out, got, sizeof got, &len) == LWP_EBADMSG, "超大 size 同样拒绝");
}

static void test_full(lwp_channel* ch, uint32_t slots) {
    printf("== 满队列与丢弃计数\n");
    lwp_stats st0, st1;
    lwp_get_stats(ch, &st0);
    lwp_header h = mk(9, 1, 0);
    uint8_t b[1] = {0};
    uint32_t ok = 0, again = 0;
    for (uint32_t i = 0; i < slots * 2; i++) {
        int rc = lwp_send(ch, LWP_EVENT, &h, b, 0);
        if (rc == LWP_OK) ok++;
        else if (rc == LWP_EAGAIN) again++;
    }
    OK(ok == slots, "队列容量正好是 slots");
    OK(again == slots, "超出后返回 EAGAIN");

    /* 可丢弃消息：满时计入 dropped */
    lwp_header d = mk(9, 2, LWP_F_DROPPABLE);
    OK(lwp_send(ch, LWP_EVENT, &d, NULL, 0) == LWP_EAGAIN, "可丢弃消息满时也返回 EAGAIN");
    lwp_get_stats(ch, &st1);
    OK(st1.dropped == st0.dropped + 1, "dropped 计数 +1");

    /* 清空 */
    lwp_header out;
    uint32_t len;
    while (lwp_recv(ch, LWP_EVENT, &out, NULL, 0, &len) == LWP_OK) {}
}

/* 3：多生产者 */
typedef struct {
    lwp_channel* ch;
    int id;
    int n;
} prod_arg;

static void* producer(void* p) {
    prod_arg* a = (prod_arg*)p;
    uint8_t body[16];
    memset(body, a->id, sizeof body);
    for (int i = 0; i < a->n; i++) {
        lwp_header h = mk(11, (uint16_t)a->id, 0);
        h.serial = (uint32_t)(a->id * 1000000 + i);
        int rc;
        while ((rc = lwp_send(a->ch, LWP_EVENT, &h, body, sizeof body)) == LWP_EAGAIN) {
            /* 消费不掉就自旋重试：本测试由主线程并行消费 */
            sched_yield();
        }
        if (rc != LWP_OK) { printf("producer send rc=%d\n", rc); break; }
    }
    return NULL;
}

static void test_mpsc(lwp_channel* ch, uint32_t slots) {
    printf("== 多生产者（4 线程 x 2000）\n");
    const int P = 4, N = 2000;
    prod_arg args[4];
    pthread_t th[4];
    for (int i = 0; i < P; i++) {
        args[i].ch = ch; args[i].id = i + 1; args[i].n = N;
        pthread_create(&th[i], NULL, producer, &args[i]);
    }
    int per_producer[5] = {0};
    int last_serial[5] = {0};
    int bad_order = 0;
    int received = 0;
    while (received < P * N) {
        lwp_header out;
        uint8_t body[32];
        uint32_t len = 0;
        int rc = lwp_recv(ch, LWP_EVENT, &out, body, sizeof body, &len);
        if (rc == LWP_EAGAIN) { sched_yield(); continue; }
        if (rc != LWP_OK) break;
        int id = out.iface == 11 ? out.opcode : -1;
        if (id < 1 || id > P) { bad_order++; continue; }
        if ((int)out.serial <= last_serial[id]) bad_order++;
        last_serial[id] = (int)out.serial;
        per_producer[id]++;
        received++;
    }
    for (int i = 0; i < P; i++) pthread_join(th[i], NULL);
    OK(received == P * N, "全部消息收到");
    OK(bad_order == 0, "每生产者内部按序、无串扰");
    for (int i = 1; i <= P; i++) {
        char msg[64];
        snprintf(msg, sizeof msg, "producer %d 收到 %d 条", i, per_producer[i]);
        OK(per_producer[i] == N, msg);
    }
    (void)slots;
}

static void test_blob(lwp_channel* ch) {
    printf("== blob\n");
    char big[900];
    memset(big, 'x', sizeof big);
    memcpy(big, "hello-blob", 10);
    uint32_t h = lwp_blob_put(ch, big, sizeof big);
    OK(h != 0, "blob_put 得到句柄");
    char out[1024];
    uint32_t len = 0;
    OK(lwp_blob_get(ch, h, out, sizeof out, &len) == LWP_OK, "blob_get 成功");
    OK(len == sizeof big && memcmp(out, big, sizeof big) == 0, "blob 内容一致");
    OK(lwp_blob_get(ch, 0, out, sizeof out, &len) == LWP_ENOENT, "句柄 0 无效");
    OK(lwp_blob_get(ch, LWP_BLOB_MAX_BLOCKS + 1, out, sizeof out, &len) == LWP_ENOENT, "越界句柄无效");
    lwp_blob_release(ch, h);
    OK(lwp_blob_get(ch, h, out, sizeof out, &len) == LWP_ENOENT, "释放后无效");
    /* 释放后应可复用同一块 */
    uint32_t h2 = lwp_blob_put(ch, big, 16);
    OK(h2 == h, "释放后句柄可复用");
    lwp_blob_release(ch, h2);
    /* 超长载荷拒绝 */
    OK(lwp_blob_put(ch, big, LWP_BLOB_BLOCK_SIZE + 1) == 0, "超过块大小的 blob 被拒");

    /* 内联上限 */
    static uint8_t too_big[LWP_INLINE_MAX + 1];
    lwp_header hd = mk(1, 1, 0);
    OK(lwp_send(ch, LWP_EVENT, &hd, too_big, sizeof too_big) == LWP_EMSGSIZE, "超过内联上限返回 EMSGSIZE");
}

static void test_wait(lwp_channel* ch) {
    printf("== wait / wake\n");
    uint64_t t0 = lwp_now_ns();
    int rc = lwp_wait(ch, LWP_EVENT, 30);
    uint64_t dt = (lwp_now_ns() - t0) / 1000000ull;
    OK(rc == LWP_EAGAIN, "空队列 wait 超时返回 EAGAIN");
    OK(dt >= 25 && dt < 500, "超时时间合理（约 30ms）");

    lwp_header h = mk(1, 2, 0);
    OK(lwp_send(ch, LWP_EVENT, &h, NULL, 0) == LWP_OK, "send 唤醒");
    t0 = lwp_now_ns();
    rc = lwp_wait(ch, LWP_EVENT, 1000);
    dt = (lwp_now_ns() - t0) / 1000000ull;
    OK(rc == LWP_OK, "有数据时 wait 立即返回");
    OK(dt < 100, "立即返回（<100ms）");
    lwp_header out; uint32_t len;
    lwp_recv(ch, LWP_EVENT, &out, NULL, 0, &len);

    /* wake 是“打断正在等待的对端”，不是“留下一个永久信号”：
       先 wake 再 wait 不应虚假返回（否则消费方会空转）。 */
    OK(lwp_wake(ch, LWP_EVENT) == LWP_OK, "显式 wake");
    OK(lwp_wait(ch, LWP_EVENT, 30) == LWP_EAGAIN, "wake 之后的空 wait 仍按超时返回（无虚假唤醒）");
}

typedef struct {
    lwp_channel* ch;
    int rc;
} wait_arg;

static void* waiter(void* p) {
    wait_arg* a = (wait_arg*)p;
    a->rc = lwp_wait(a->ch, LWP_EVENT, 2000);
    return NULL;
}

static void test_wake_blocked(lwp_channel* ch) {
    printf("== 打断阻塞中的 wait\n");
    wait_arg a = { ch, 999 };
    pthread_t th;
    pthread_create(&th, NULL, waiter, &a);
    usleep(30 * 1000);
    uint64_t t0 = lwp_now_ns();
    OK(lwp_wake(ch, LWP_EVENT) == LWP_OK, "从另一线程 wake");
    pthread_join(th, NULL);
    uint64_t dt = (lwp_now_ns() - t0) / 1000000ull;
    OK(a.rc == LWP_OK, "被唤醒的 wait 返回 LWP_OK");
    OK(dt < 200, "及时返回（<200ms，未等到 2s 超时）");
}

/* 检查器：握手前禁止非 core 消息；未知 core opcode 计数 */
static void test_checker(lwp_channel* ch) {
    printf("== 协议检查器\n");
    lwp_stats s0, s1;
    lwp_get_stats(ch, &s0);
    OK(lwp_checker_enable(ch, 1) == LWP_OK, "启用严格检查器");

    lwp_header seat = mk(2, 0, 0);          /* 非 core 接口（iface 2 尚未定义） */
    uint8_t b[4] = {0};
    OK(lwp_send(ch, LWP_EVENT, &seat, b, sizeof b) == LWP_EPROTO, "握手前发非 core 消息被拒");
    lwp_get_stats(ch, &s1);
    OK(s1.not_handshaked == s0.not_handshaked + 1, "not_handshaked 计数 +1");

    /* 壳发 core.hello（iface=1 opcode=0）后放行 */
    lwp_header hello = mk(1, 0, 0);
    OK(lwp_send(ch, LWP_EVENT, &hello, b, sizeof b) == LWP_OK, "握手消息本身放行");
    OK(lwp_send(ch, LWP_EVENT, &seat, b, sizeof b) == LWP_OK, "握手后非 core 消息放行");

    /* 未知 core opcode（当前 core.event 只定义到 pong=3） */
    lwp_header badop = mk(1, 99, 0);
    OK(lwp_send(ch, LWP_EVENT, &badop, b, sizeof b) == LWP_EPROTO, "未知 core opcode 被拒");
    lwp_get_stats(ch, &s1);
    OK(s1.unknown_opcode >= 1, "unknown_opcode 计数 >= 1");

    /* 引擎侧：hello_ack 之前 REQUEST 方向的非 core 也被拒 */
    lwp_header req = mk(2, 0, 0);
    OK(lwp_send(ch, LWP_REQUEST, &req, b, sizeof b) == LWP_EPROTO, "引擎未 ack 前发请求被拒");
    lwp_header ack = mk(1, 0, 0);
    OK(lwp_send(ch, LWP_REQUEST, &ack, b, sizeof b) == LWP_OK, "hello_ack 放行");
    OK(lwp_send(ch, LWP_REQUEST, &req, b, sizeof b) == LWP_OK, "ack 后请求放行");

    /* 清空 */
    lwp_header out; uint32_t len;
    while (lwp_recv(ch, LWP_EVENT, &out, NULL, 0, &len) == LWP_OK) {}
    while (lwp_recv(ch, LWP_REQUEST, &out, NULL, 0, &len) == LWP_OK) {}
}

/* 录制：写 .lwtrace，校验文件头与记录数（内容由 tools/lwtrace.py 解析） */
static void test_trace(lwp_channel* ch, const char* path) {
    printf("== 录制\n");
    OK(lwp_trace_open(ch, path) == LWP_OK, "打开录制");
    uint8_t b[8] = {1,2,3,4,5,6,7,8};
    lwp_header h = mk(1, 0, 0);
    for (int i = 0; i < 3; i++) {
        lwp_send(ch, LWP_EVENT, &h, b, sizeof b);
        lwp_header out; uint32_t len;
        lwp_recv(ch, LWP_EVENT, &out, b, sizeof b, &len);
    }
    lwp_trace_close(ch);
    FILE* f = fopen(path, "rb");
    OK(f != NULL, "录制文件存在");
    if (f) {
        char magic[4] = {0};
        size_t n = fread(magic, 1, 4, f);
        OK(n == 4 && memcmp(magic, "LWPT", 4) == 0, "文件头 magic=LWPT");
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fclose(f);
        /* 头 8B + 每条记录 (32B + 8B payload)；3 轮 × (send+recv) = 6 条 */
        OK(sz == 8 + 6 * (32 + 8), "记录数与格式符合预期（6 条）");
    }

    /* 回放：把“发送”记录重新入队（3 条 send → 3 条新消息） */
    int n = lwp_trace_replay(ch, path, LWP_EVENT);
    OK(n == 3, "回放条数 = 录制里的发送记录数");
    lwp_header out; uint32_t len; uint8_t buf[64];
    int got = 0;
    while (lwp_recv(ch, LWP_EVENT, &out, buf, sizeof buf, &len) == LWP_OK) got++;
    OK(got == 3, "回放产生 3 条可收消息");
    OK(lwp_trace_replay(ch, "/nonexistent.lwtrace", LWP_EVENT) == LWP_EINVAL, "不存在的文件返回 EINVAL");
}

int main(void) {
    uint32_t slots = 64;
    lwp_channel* a = NULL;
    lwp_channel* b = NULL;
    OK(lwp_open("test", slots, &a) == LWP_OK, "lwp_open");
    OK(lwp_open("test", slots, &b) == LWP_OK, "重复 open 成功");
    OK(a == b, "同名返回同一实例（进程内单例）");

    test_basic(a);
    test_full(a, slots);
    test_mpsc(a, slots);
    test_blob(a);
    test_wait(a);
    test_wake_blocked(a);
    const char* trace_path = getenv("LWP_TRACE_PATH");
    test_trace(a, trace_path ? trace_path : "channel.lwtrace");
    test_checker(a);

    lwp_stats st;
    lwp_get_stats(a, &st);
    printf("== 统计：sent=%llu recv=%llu dropped=%llu bad=%llu wake=%llu depth=(e%u r%u)\n",
           (unsigned long long)st.sent, (unsigned long long)st.recv,
           (unsigned long long)st.dropped, (unsigned long long)st.bad,
           (unsigned long long)st.wake, st.depth_event, st.depth_request);

    lwp_close(a);
    printf("\n%s\n", g_fail ? "[FAIL] liblwp 通道测试" : "[PASS] liblwp 通道测试");
    return g_fail ? 1 : 0;
}
