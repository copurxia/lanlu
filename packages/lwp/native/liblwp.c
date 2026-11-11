/* liblwp —— 通道实现。计划 §5.2。
 *
 * 设计要点：
 *   * 定长槽环形队列（Vyukov 有界 MPMC：每槽一个 seq 序号），EVENT 多生产者/单消费者，
 *     REQUEST 单生产者/单消费者，同一份代码；满队列返回 LWP_EAGAIN，不阻塞。
 *   * 消息载荷内联上限 LWP_INLINE_MAX；更大载荷走 blob 池（句柄放 payload 首 4 字节）。
 *   * 每个方向一个 eventfd 做唤醒；wait 用 poll，真阻塞（取代 4ms 轮询读文件）。
 *   * 纯 C、零构造函数：首次 lwp_open 时才分配；进程内单例由互斥锁保护。
 */
#define _GNU_SOURCE
#include "../include/lwp.h"
#include "../include/lwp_protocol.h"

#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <unistd.h>
#include <sched.h>
#include <stdio.h>
#include <poll.h>
#include <time.h>

#define LWP_MAGIC 0x4c575031u /* "LWP1" */

typedef struct {
    _Atomic uint32_t seq;
    uint32_t len;
    lwp_header hdr;
    uint8_t payload[LWP_INLINE_MAX];
} lwp_slot;

typedef struct {
    uint32_t mask;   /* slots - 1 */
    uint32_t cap;    /* slots */
    lwp_slot* slots;
    _Atomic uint32_t enq;
    _Atomic uint32_t deq;
    _Atomic uint64_t dropped;
} lwp_queue;

typedef struct {
    int used;
    uint32_t len;
    uint8_t* data;   /* 指向 arena 内偏移 */
} lwp_blob;

struct lwp_channel {
    uint32_t magic;
    char name[64];
    lwp_queue q[2];              /* [LWP_REQUEST], [LWP_EVENT] */
    int efd[2];
    uint8_t* arena;
    lwp_blob blobs[LWP_BLOB_MAX_BLOCKS];
    pthread_mutex_t blob_lock;
    _Atomic uint32_t next_serial[2];
    _Atomic uint64_t sent, recv, bad, wake;
    _Atomic uint64_t wake_seq;
    /* 协议检查器（计划 §16.7） */
    int check_on;
    int check_strict;
    _Atomic int hs_shell_hello;   /* 壳已发 core.hello */
    _Atomic int hs_engine_ack;    /* 引擎已发 core.hello_ack */
    _Atomic uint64_t n_unknown;
    _Atomic uint64_t n_not_hs;
    /* 录制（计划 §16.3） */
    FILE* trace;
    pthread_mutex_t trace_lock;
};

/* ── 单例注册表 ────────────────────────────────────────────────────────────── */
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static lwp_channel* g_chans[8];
static int g_nchan = 0;

uint64_t lwp_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

/* ── 队列 ──────────────────────────────────────────────────────────────────── */
static int queue_init(lwp_queue* q, uint32_t slots) {
    uint32_t cap = 1;
    while (cap < slots) cap <<= 1;         /* 2 的幂，便于取模 */
    q->cap = cap;
    q->mask = cap - 1;
    q->slots = (lwp_slot*)calloc(cap, sizeof(lwp_slot));
    if (!q->slots) return LWP_EINVAL;
    for (uint32_t i = 0; i < cap; i++) atomic_init(&q->slots[i].seq, i);
    atomic_init(&q->enq, 0);
    atomic_init(&q->deq, 0);
    atomic_init(&q->dropped, 0);
    return LWP_OK;
}

static void queue_free(lwp_queue* q) {
    free(q->slots);
    q->slots = NULL;
}

static uint32_t queue_depth(lwp_queue* q) {
    uint32_t e = atomic_load_explicit(&q->enq, memory_order_relaxed);
    uint32_t d = atomic_load_explicit(&q->deq, memory_order_relaxed);
    return e - d;
}

static int queue_push(lwp_queue* q, const lwp_header* hdr, const void* body, uint32_t len) {
    if (len > LWP_INLINE_MAX) return LWP_EMSGSIZE;
    uint32_t pos = atomic_load_explicit(&q->enq, memory_order_relaxed);
    lwp_slot* slot;
    for (;;) {
        slot = &q->slots[pos & q->mask];
        uint32_t s = atomic_load_explicit(&slot->seq, memory_order_acquire);
        int32_t dif = (int32_t)(s - pos);
        if (dif == 0) {
            if (atomic_compare_exchange_weak_explicit(&q->enq, &pos, pos + 1,
                                                      memory_order_relaxed,
                                                      memory_order_relaxed)) {
                break;
            }
        } else if (dif < 0) {
            return LWP_EAGAIN;   /* 满 */
        } else {
            pos = atomic_load_explicit(&q->enq, memory_order_relaxed);
        }
    }
    slot->len = len;
    slot->hdr = *hdr;
    if (len && body) memcpy(slot->payload, body, len);
    atomic_store_explicit(&slot->seq, pos + 1, memory_order_release);
    return LWP_OK;
}

static int queue_pop(lwp_queue* q, lwp_header* hdr, void* body, uint32_t cap, uint32_t* out_len) {
    uint32_t pos = atomic_load_explicit(&q->deq, memory_order_relaxed);
    lwp_slot* slot;
    for (;;) {
        slot = &q->slots[pos & q->mask];
        uint32_t s = atomic_load_explicit(&slot->seq, memory_order_acquire);
        int32_t dif = (int32_t)(s - (pos + 1));
        if (dif == 0) {
            if (atomic_compare_exchange_weak_explicit(&q->deq, &pos, pos + 1,
                                                      memory_order_relaxed,
                                                      memory_order_relaxed)) {
                break;
            }
        } else if (dif < 0) {
            return LWP_EAGAIN;   /* 空 */
        } else {
            pos = atomic_load_explicit(&q->deq, memory_order_relaxed);
        }
    }
    uint32_t len = slot->len;
    *hdr = slot->hdr;
    if (out_len) *out_len = len;
    if (body && cap) {
        uint32_t n = len < cap ? len : cap;
        if (n) memcpy(body, slot->payload, n);
    }
    atomic_store_explicit(&slot->seq, pos + q->cap, memory_order_release);
    return len > cap ? LWP_EMSGSIZE : LWP_OK;
}

/* ── 通道生命周期 ──────────────────────────────────────────────────────────── */
int lwp_open(const char* name, uint32_t slots, lwp_channel** out) {
    if (!name || !out) return LWP_EINVAL;
    if (slots == 0) slots = 256;
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_nchan; i++) {
        if (g_chans[i] && strncmp(g_chans[i]->name, name, sizeof(g_chans[i]->name)) == 0) {
            *out = g_chans[i];
            pthread_mutex_unlock(&g_lock);
            return LWP_OK;
        }
    }
    if (g_nchan >= (int)(sizeof(g_chans) / sizeof(g_chans[0]))) {
        pthread_mutex_unlock(&g_lock);
        return LWP_EINVAL;
    }
    lwp_channel* ch = (lwp_channel*)calloc(1, sizeof(lwp_channel));
    if (!ch) { pthread_mutex_unlock(&g_lock); return LWP_EINVAL; }
    ch->magic = LWP_MAGIC;
    strncpy(ch->name, name, sizeof(ch->name) - 1);
    if (queue_init(&ch->q[LWP_REQUEST], slots) != LWP_OK ||
        queue_init(&ch->q[LWP_EVENT], slots) != LWP_OK) {
        free(ch);
        pthread_mutex_unlock(&g_lock);
        return LWP_EINVAL;
    }
    ch->efd[LWP_REQUEST] = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    ch->efd[LWP_EVENT] = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (ch->efd[0] < 0 || ch->efd[1] < 0) {
        if (ch->efd[0] >= 0) close(ch->efd[0]);
        if (ch->efd[1] >= 0) close(ch->efd[1]);
        queue_free(&ch->q[0]);
        queue_free(&ch->q[1]);
        free(ch);
        pthread_mutex_unlock(&g_lock);
        return LWP_EINVAL;
    }
    ch->arena = (uint8_t*)calloc(LWP_BLOB_MAX_BLOCKS, LWP_BLOB_BLOCK_SIZE);
    pthread_mutex_init(&ch->blob_lock, NULL);
    pthread_mutex_init(&ch->trace_lock, NULL);
    atomic_init(&ch->hs_shell_hello, 0);
    atomic_init(&ch->hs_engine_ack, 0);
    atomic_init(&ch->n_unknown, 0);
    atomic_init(&ch->n_not_hs, 0);
    atomic_init(&ch->next_serial[0], 1);
    atomic_init(&ch->next_serial[1], 1);
    atomic_init(&ch->sent, 0);
    atomic_init(&ch->recv, 0);
    atomic_init(&ch->bad, 0);
    atomic_init(&ch->wake, 0);
    atomic_init(&ch->wake_seq, 0);
    g_chans[g_nchan++] = ch;
    *out = ch;
    pthread_mutex_unlock(&g_lock);
    return LWP_OK;
}

void lwp_close(lwp_channel* ch) {
    if (!ch || ch->magic != LWP_MAGIC) return;
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_nchan; i++) {
        if (g_chans[i] == ch) {
            for (int j = i; j + 1 < g_nchan; j++) g_chans[j] = g_chans[j + 1];
            g_nchan--;
            break;
        }
    }
    pthread_mutex_unlock(&g_lock);
    ch->magic = 0;
    queue_free(&ch->q[0]);
    queue_free(&ch->q[1]);
    if (ch->efd[0] >= 0) close(ch->efd[0]);
    if (ch->efd[1] >= 0) close(ch->efd[1]);
    free(ch->arena);
    pthread_mutex_destroy(&ch->blob_lock);
    if (ch->trace) { fclose(ch->trace); ch->trace = NULL; }
    pthread_mutex_destroy(&ch->trace_lock);
    free(ch);
}

/* ── 检查器与录制 ──────────────────────────────────────────────────────────── */
int lwp_checker_enable(lwp_channel* ch, int strict) {
    if (!ch || ch->magic != LWP_MAGIC) return LWP_EINVAL;
    ch->check_strict = strict ? 1 : 0;
    ch->check_on = 1;
    return LWP_OK;
}

/* 握手规则（计划 §5.3）：core 接口永远放行；非 core 消息要求本侧已完成握手。
 *
 * 注意：检查器只看得到**本侧发出的消息**（send 路径），所以「本侧握手完成」的判定必须
 * 基于本侧发出过 hello / hello_ack，而不是「收到过」。早期版本按收到来判断，
 * 结果引擎侧（只发 hello_ack、永不收 ack）的每条消息都被记成 notHandshaked ——
 * 真机上表现为这个计数与 recv 同步增长（第 52 轮发现）。 */
static int checker_admit(lwp_channel* ch, int dir, const lwp_header* h) {
    if (!ch->check_on) return LWP_OK;
    /* 发出握手消息即认为本侧完成握手 */
    if (h->iface == LWP_IFACE_LW_CORE) {
        if (dir == LWP_EVENT && h->opcode == LWP_LW_CORE_HELLO_OPCODE) {
            atomic_store(&ch->hs_shell_hello, 1);
        }
        if (dir == LWP_REQUEST && h->opcode == LWP_LW_CORE_HELLO_ACK_OPCODE) {
            atomic_store(&ch->hs_engine_ack, 1);
        }
    }
    if (h->iface != LWP_IFACE_LW_CORE) {
        int ok = (dir == LWP_EVENT) ? atomic_load(&ch->hs_shell_hello)
                                    : atomic_load(&ch->hs_engine_ack);
        if (!ok) {
            atomic_fetch_add(&ch->n_not_hs, 1);
            return ch->check_strict ? LWP_EPROTO : LWP_OK;
        }
        return LWP_OK;
    }
    /* core：只承认本版本定义过的 opcode */
    uint32_t max_op = (dir == LWP_EVENT) ? LWP_LW_CORE_PONG_OPCODE : LWP_LW_CORE_HELLO_ACK_OPCODE;
    if (h->opcode > max_op) {
        atomic_fetch_add(&ch->n_unknown, 1);
        return ch->check_strict ? LWP_EPROTO : LWP_OK;
    }
    if (dir == LWP_EVENT && h->opcode == LWP_LW_CORE_HELLO_OPCODE) atomic_store(&ch->hs_shell_hello, 1);
    if (dir == LWP_REQUEST && h->opcode == LWP_LW_CORE_HELLO_ACK_OPCODE) atomic_store(&ch->hs_engine_ack, 1);
    return LWP_OK;
}

static void trace_record(lwp_channel* ch, int kind, int dir, const lwp_header* h,
                         const void* body, uint32_t len) {
    if (!ch->trace) return;
    /* packed：与 tools/lwtrace.py 的 '<BBHHHIIIQI' 一一对应（不依赖编译器对齐习惯） */
    struct __attribute__((packed)) { uint8_t kind, dir; uint16_t pad; lwp_header h; uint32_t len; } rec;
    memset(&rec, 0, sizeof rec);
    rec.kind = (uint8_t)kind;
    rec.dir = (uint8_t)dir;
    rec.h = *h;
    rec.len = len;
    pthread_mutex_lock(&ch->trace_lock);
    fwrite(&rec, sizeof rec, 1, ch->trace);
    if (len && body) fwrite(body, 1, len, ch->trace);
    fflush(ch->trace);   /* 崩溃后仍能取回最近的记录（崩溃取证，计划 §16.7） */
    pthread_mutex_unlock(&ch->trace_lock);
}

int lwp_trace_open(lwp_channel* ch, const char* path) {
    if (!ch || ch->magic != LWP_MAGIC || !path) return LWP_EINVAL;
    pthread_mutex_lock(&ch->trace_lock);
    if (ch->trace) { fclose(ch->trace); ch->trace = NULL; }
    FILE* f = fopen(path, "wb");
    if (!f) { pthread_mutex_unlock(&ch->trace_lock); return LWP_EINVAL; }
    const char magic[4] = {'L', 'W', 'P', 'T'};
    uint16_t v[2] = { (uint16_t)LWP_PROTOCOL_MAJOR, (uint16_t)LWP_PROTOCOL_MINOR };
    fwrite(magic, 1, 4, f);
    fwrite(v, sizeof v, 1, f);
    ch->trace = f;
    pthread_mutex_unlock(&ch->trace_lock);
    return LWP_OK;
}

void lwp_trace_close(lwp_channel* ch) {
    if (!ch || ch->magic != LWP_MAGIC) return;
    pthread_mutex_lock(&ch->trace_lock);
    if (ch->trace) { fclose(ch->trace); ch->trace = NULL; }
    pthread_mutex_unlock(&ch->trace_lock);
}

int lwp_trace_replay(lwp_channel* ch, const char* path, int dir_filter) {
    if (!ch || ch->magic != LWP_MAGIC || !path) return LWP_EINVAL;
    FILE* f = fopen(path, "rb");
    if (!f) return LWP_EINVAL;
    char magic[4];
    uint16_t ver[2];
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "LWPT", 4) != 0 ||
        fread(ver, sizeof ver, 1, f) != 1) {
        fclose(f);
        return LWP_EBADMSG;
    }
    struct __attribute__((packed)) {
        uint8_t kind, dir;
        uint16_t pad;
        lwp_header h;
        uint32_t len;
    } rec;
    uint8_t payload[LWP_INLINE_MAX];
    int n = 0;
    while (fread(&rec, sizeof rec, 1, f) == 1) {
        if (rec.len > LWP_INLINE_MAX) {   /* 损坏/越界：停止而不是读爆缓冲 */
            fclose(f);
            return LWP_EBADMSG;
        }
        if (rec.len && fread(payload, 1, rec.len, f) != rec.len) break;
        if (rec.kind != 0) continue;                       /* 只回放“发送”的记录 */
        if (dir_filter >= 0 && rec.dir != (uint8_t)dir_filter) continue;
        lwp_header h;
        memcpy(&h, &rec.h, sizeof h);   /* record 是 packed，避免取非对齐成员地址 */
        int rc = lwp_send(ch, rec.dir, &h, payload, rec.len);
        if (rc != LWP_OK && rc != LWP_EAGAIN) { fclose(f); return rc; }
        n++;
    }
    fclose(f);
    return n;
}

/* ── 收发 ──────────────────────────────────────────────────────────────────── */
static int notify(lwp_channel* ch, int dir) {
    uint64_t one = 1;
    ssize_t n = write(ch->efd[dir], &one, sizeof one);
    (void)n;  /* 计数溢出（EAGAIN）说明已有待唤醒，忽略即可 */
    return LWP_OK;
}

int lwp_send(lwp_channel* ch, int dir, const lwp_header* hdr, const void* body, uint32_t len) {
    if (!ch || ch->magic != LWP_MAGIC || !hdr) return LWP_EINVAL;
    if (dir != LWP_REQUEST && dir != LWP_EVENT) return LWP_EINVAL;
    if (len > LWP_INLINE_MAX) return LWP_EMSGSIZE;

    lwp_header h = *hdr;
    h.size = (uint32_t)sizeof(lwp_header) + len;
    if (h.serial == 0) h.serial = atomic_fetch_add_explicit(&ch->next_serial[dir], 1, memory_order_relaxed);
    if (h.time_ns == 0) h.time_ns = lwp_now_ns();

    int crc = checker_admit(ch, dir, &h);
    if (crc != LWP_OK) return crc;

    int rc = queue_push(&ch->q[dir], &h, body, len);
    if (rc == LWP_EAGAIN) {
        if (h.flags & LWP_F_DROPPABLE) atomic_fetch_add(&ch->q[dir].dropped, 1);
        return LWP_EAGAIN;
    }
    if (rc != LWP_OK) return rc;
    atomic_fetch_add(&ch->sent, 1);
    trace_record(ch, 0, dir, &h, body, len);
    notify(ch, dir);
    return LWP_OK;
}

int lwp_recv(lwp_channel* ch, int dir, lwp_header* hdr, void* body, uint32_t cap, uint32_t* out_len) {
    if (!ch || ch->magic != LWP_MAGIC || !hdr) return LWP_EINVAL;
    if (dir != LWP_REQUEST && dir != LWP_EVENT) return LWP_EINVAL;
    int rc = queue_pop(&ch->q[dir], hdr, body, cap, out_len);
    if (rc == LWP_EAGAIN) return LWP_EAGAIN;
    /* 头部自洽性：size 必须覆盖头部且不超过“头部 + 内联上限” */
    if (hdr->size < sizeof(lwp_header) || hdr->size > sizeof(lwp_header) + LWP_INLINE_MAX) {
        atomic_fetch_add(&ch->bad, 1);
        return LWP_EBADMSG;
    }
    atomic_fetch_add(&ch->recv, 1);
    if (ch->trace) {
        uint32_t plen = hdr->size > sizeof(lwp_header) ? hdr->size - (uint32_t)sizeof(lwp_header) : 0;
        if (plen > cap) plen = cap;
        trace_record(ch, 1, dir, hdr, body, plen);
    }
    return rc;
}

int lwp_send_parts(lwp_channel* ch, int dir, uint16_t iface, uint16_t opcode,
                   uint32_t flags, const void* body, uint32_t len) {
    lwp_header h;
    memset(&h, 0, sizeof h);
    h.iface = iface;
    h.opcode = opcode;
    h.flags = flags;
    return lwp_send(ch, dir, &h, body, len);
}

int lwp_recv_parts(lwp_channel* ch, int dir, uint16_t* iface, uint16_t* opcode,
                   uint32_t* flags, uint64_t* time_ns, void* body, uint32_t cap,
                   uint32_t* out_len) {
    lwp_header h;
    memset(&h, 0, sizeof h);
    uint32_t len = 0;
    int rc = lwp_recv(ch, dir, &h, body, cap, &len);
    if (rc == LWP_OK || rc == LWP_EMSGSIZE) {
        if (iface) *iface = h.iface;
        if (opcode) *opcode = h.opcode;
        if (flags) *flags = h.flags;
        if (time_ns) *time_ns = h.time_ns;
        if (out_len) *out_len = len;
    }
    return rc;
}

int lwp_wait(lwp_channel* ch, int dir, int timeout_ms) {
    if (!ch || ch->magic != LWP_MAGIC) return LWP_EINVAL;
    if (dir != LWP_REQUEST && dir != LWP_EVENT) return LWP_EINVAL;
    uint64_t wake0 = atomic_load_explicit(&ch->wake_seq, memory_order_relaxed);
    uint64_t deadline = timeout_ms < 0 ? 0 : lwp_now_ns() + (uint64_t)timeout_ms * 1000000ull;
    for (;;) {
        if (queue_depth(&ch->q[dir]) > 0) return LWP_OK;
        if (atomic_load_explicit(&ch->wake_seq, memory_order_relaxed) != wake0) return LWP_OK;
        int wait_ms = -1;
        if (timeout_ms >= 0) {
            uint64_t now = lwp_now_ns();
            if (now >= deadline) return LWP_EAGAIN;
            wait_ms = (int)((deadline - now) / 1000000ull);
        }
        struct pollfd p = { .fd = ch->efd[dir], .events = POLLIN };
        int rc = poll(&p, 1, wait_ms);
        if (rc > 0) {
            uint64_t v;
            ssize_t n = read(ch->efd[dir], &v, sizeof v);   /* 清掉陈旧计数 */
            (void)n;
        } else if (rc == 0) {
            return LWP_EAGAIN;   /* 超时 */
        }
        /* rc < 0：EINTR 等，循环里用 deadline 兜底 */
    }
}

int lwp_wake(lwp_channel* ch, int dir) {
    if (!ch || ch->magic != LWP_MAGIC) return LWP_EINVAL;
    if (dir != LWP_REQUEST && dir != LWP_EVENT) return LWP_EINVAL;
    atomic_fetch_add(&ch->wake, 1);
    atomic_fetch_add(&ch->wake_seq, 1);
    return notify(ch, dir);
}

/* ── blob ──────────────────────────────────────────────────────────────────── */
uint32_t lwp_blob_put(lwp_channel* ch, const void* data, uint32_t len) {
    if (!ch || ch->magic != LWP_MAGIC || (!data && len)) return 0;
    if (len > LWP_BLOB_BLOCK_SIZE) return 0;
    pthread_mutex_lock(&ch->blob_lock);
    for (uint32_t i = 0; i < LWP_BLOB_MAX_BLOCKS; i++) {
        if (!ch->blobs[i].used) {
            memcpy(ch->arena + (size_t)i * LWP_BLOB_BLOCK_SIZE, data, len);
            ch->blobs[i].used = 1;
            ch->blobs[i].len = len;
            pthread_mutex_unlock(&ch->blob_lock);
            return i + 1;   /* 句柄从 1 开始，0 表示失败 */
        }
    }
    pthread_mutex_unlock(&ch->blob_lock);
    return 0;
}

int lwp_blob_get(lwp_channel* ch, uint32_t handle, void* out, uint32_t cap, uint32_t* out_len) {
    if (!ch || ch->magic != LWP_MAGIC || handle == 0 || handle > LWP_BLOB_MAX_BLOCKS) return LWP_ENOENT;
    uint32_t i = handle - 1;
    pthread_mutex_lock(&ch->blob_lock);
    if (!ch->blobs[i].used) { pthread_mutex_unlock(&ch->blob_lock); return LWP_ENOENT; }
    uint32_t len = ch->blobs[i].len;
    if (out_len) *out_len = len;
    if (out && cap) memcpy(out, ch->arena + (size_t)i * LWP_BLOB_BLOCK_SIZE, len < cap ? len : cap);
    pthread_mutex_unlock(&ch->blob_lock);
    return len > cap ? LWP_EMSGSIZE : LWP_OK;
}

void lwp_blob_release(lwp_channel* ch, uint32_t handle) {
    if (!ch || ch->magic != LWP_MAGIC || handle == 0 || handle > LWP_BLOB_MAX_BLOCKS) return;
    pthread_mutex_lock(&ch->blob_lock);
    ch->blobs[handle - 1].used = 0;
    ch->blobs[handle - 1].len = 0;
    pthread_mutex_unlock(&ch->blob_lock);
}

#ifdef LWP_TEST_HOOKS
int lwp__test_push_raw(lwp_channel* ch, int dir, const lwp_header* hdr, const void* body, uint32_t len) {
    if (!ch || ch->magic != LWP_MAGIC || !hdr) return LWP_EINVAL;
    if (dir != LWP_REQUEST && dir != LWP_EVENT) return LWP_EINVAL;
    int rc = queue_push(&ch->q[dir], hdr, body, len);
    if (rc == LWP_OK) notify(ch, dir);
    return rc;
}
#endif

int lwp_stats_summary(lwp_channel* ch, char* out, uint32_t cap) {
    if (!ch || ch->magic != LWP_MAGIC || !out || cap == 0) return -1;
    lwp_stats st;
    lwp_get_stats(ch, &st);
    int n = snprintf(out, cap,
                     "sent=%llu recv=%llu dropped=%llu bad=%llu unknown=%llu notHandshaked=%llu wake=%llu depthE=%u depthR=%u",
                     (unsigned long long)st.sent, (unsigned long long)st.recv,
                     (unsigned long long)st.dropped, (unsigned long long)st.bad,
                     (unsigned long long)st.unknown_opcode, (unsigned long long)st.not_handshaked,
                     (unsigned long long)st.wake, st.depth_event, st.depth_request);
    return n;
}

void lwp_get_stats(lwp_channel* ch, lwp_stats* out) {
    if (!ch || !out || ch->magic != LWP_MAGIC) return;
    out->sent = atomic_load(&ch->sent);
    out->recv = atomic_load(&ch->recv);
    out->dropped = atomic_load(&ch->q[LWP_EVENT].dropped) + atomic_load(&ch->q[LWP_REQUEST].dropped);
    out->bad = atomic_load(&ch->bad);
    out->wake = atomic_load(&ch->wake);
    out->unknown_opcode = atomic_load(&ch->n_unknown);
    out->not_handshaked = atomic_load(&ch->n_not_hs);
    out->depth_event = queue_depth(&ch->q[LWP_EVENT]);
    out->depth_request = queue_depth(&ch->q[LWP_REQUEST]);
}
