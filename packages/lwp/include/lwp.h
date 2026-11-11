/* lwp —— 壳 ↔ 引擎协议通道（C ABI）。计划 §5.2。
 *
 * 形态：进程内单例通道 + 双向定长槽环形队列 + blob 大面积载荷池 + eventfd 唤醒。
 * 约束（来自 docs/l-layer.md 的 M0-4 结论）：
 *   * 纯 C、无构造函数、首次调用惰性初始化；
 *   * 壳侧必须以 RTLD_GLOBAL 加载并早于引擎，engine 才能解析到本库符号；
 *   * 链路是否可用由 core.hello / hello_ack 判定，不依赖链接成功。
 *
 * 错误码：返回 0 = 成功，负值为错误。
 */
#ifndef LWP_H
#define LWP_H

#include <stdint.h>
#include <stddef.h>

#ifndef LWP_API
#define LWP_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define LWP_OK          0
#define LWP_EINVAL    (-22)
#define LWP_EAGAIN    (-11)   /* 队列满 / 无消息 */
#define LWP_EMSGSIZE  (-90)   /* 单条消息超出内联上限（请用 blob） */
#define LWP_ENOENT    (-2)    /* blob 句柄无效 */
#define LWP_ENODEV    (-19)   /* 通道未打开 */
#define LWP_EBADMSG   (-74)   /* size 越界 / 头部非法 */

/* 方向（与生成的 LWP_DIR_* 一致） */
#define LWP_REQUEST 0   /* 引擎 -> 壳 */
#define LWP_EVENT   1   /* 壳 -> 引擎 */

/* 头标志位 */
#define LWP_F_BLOB      0x1u  /* payload 首 4 字节是 blob 句柄 */
#define LWP_F_DROPPABLE 0x2u  /* 队列满时允许丢弃并计数（如高频 motion） */

/* 单条消息内联载荷上限；更大的走 blob */
#define LWP_INLINE_MAX 320u
/* blob 池：句柄 = 下标 */
#define LWP_BLOB_MAX_BLOCKS 64
#define LWP_BLOB_BLOCK_SIZE 4096u

/* 线上消息头（24 字节，与 IDL 生成物配套） */
typedef struct {
    uint16_t iface;
    uint16_t opcode;
    uint32_t size;      /* 头部 + 载荷总长；接收方据此跳过未知消息 */
    uint32_t serial;    /* 发送方单调递增 */
    uint32_t flags;     /* LWP_F_* */
    uint64_t time_ns;   /* CLOCK_MONOTONIC */
} lwp_header;

typedef struct lwp_channel lwp_channel;

typedef struct {
    uint64_t sent, recv;
    uint64_t unknown_opcode;   /* 检查器：未知 iface/opcode */
    uint64_t not_handshaked;   /* 检查器：握手前发了非 core 消息 */
    uint64_t dropped;       /* 因队列满被丢弃的可丢弃消息 */
    uint64_t bad;           /* 头部非法的消息数 */
    uint64_t wake;          /* 唤醒次数 */
    uint32_t depth_event;   /* 当前 EVENT 队列深度 */
    uint32_t depth_request;
} lwp_stats;

/* 打开（或复用）名为 name 的通道。重复调用返回同一实例。 */
LWP_API int lwp_open(const char* name, uint32_t slots, lwp_channel** out);
/* 关闭并释放（仅供测试/退出使用；进程内单例会被移除）。 */
LWP_API void lwp_close(lwp_channel* ch);

/* 发送一条消息。body 可为 NULL（len=0）。成功返回 0。
 * 队列满：可丢弃消息返回 LWP_EAGAIN 并计入 dropped；不可丢弃消息同样返回 LWP_EAGAIN（调用方可重试）。 */
LWP_API int lwp_send(lwp_channel* ch, int dir, const lwp_header* hdr, const void* body, uint32_t len);

/* ── 标量版收发（给仓颉等非 C 调用方）─────────────────────────────────────
 * FFI 边界上不传 lwp_header 结构体，只传标量与字节缓冲，避免跨语言结构体 ABI。 */
LWP_API int lwp_send_parts(lwp_channel* ch, int dir, uint16_t iface, uint16_t opcode,
                           uint32_t flags, const void* body, uint32_t len);
LWP_API int lwp_recv_parts(lwp_channel* ch, int dir, uint16_t* iface, uint16_t* opcode,
                           uint32_t* flags, uint64_t* time_ns, void* body, uint32_t cap,
                           uint32_t* out_len);

/* 收取一条消息。cap 为 body 缓冲区大小；实际长度写入 *out_len。
 * 无消息返回 LWP_EAGAIN。头部非法（size 越界）计入 bad 并返回 LWP_EBADMSG。 */
LWP_API int lwp_recv(lwp_channel* ch, int dir, lwp_header* hdr, void* body, uint32_t cap, uint32_t* out_len);

/* 等待 dir 方向有数据、或有显式 wake、或超时（timeout_ms < 0 无限等待）。
 * 返回 LWP_OK 表示可以尝试 lwp_recv；LWP_EAGAIN 表示超时。
 * 语义细节：eventfd 计数是“曾经有过事件”的残留，本函数在无数据时会继续等到超时，
 * 不会因为陈旧计数而虚假返回（测试覆盖）。 */
LWP_API int lwp_wait(lwp_channel* ch, int dir, int timeout_ms);

/* 唤醒对端（不发送消息，只打断 wait 让对端重新检查状态）。 */
LWP_API int lwp_wake(lwp_channel* ch, int dir);

/* blob：大载荷（> LWP_INLINE_MAX 的文本、文件列表、像素）。返回句柄，0 表示失败。 */
LWP_API uint32_t lwp_blob_put(lwp_channel* ch, const void* data, uint32_t len);
LWP_API int lwp_blob_get(lwp_channel* ch, uint32_t handle, void* out, uint32_t cap, uint32_t* out_len);
LWP_API void lwp_blob_release(lwp_channel* ch, uint32_t handle);

/* 统计（诊断用；`lwp_trace stats` 与协议检查器读取）。 */
LWP_API void lwp_get_stats(lwp_channel* ch, lwp_stats* out);

/* 把统计格式化成一行文本（给非 C 调用方用；不跨 FFI 传结构体）。返回写入长度。 */
LWP_API int lwp_stats_summary(lwp_channel* ch, char* out, uint32_t cap);

/* 当前单调时钟（纳秒），供发送方填 hdr.time_ns。 */
LWP_API uint64_t lwp_now_ns(void);

/* ── 协议检查器（计划 §16.7）────────────────────────────────────────────────
 * 开着时校验：未握手先发非 core 消息、未知 iface/opcode。
 * strict=1 时违规直接返回 LWP_EPROTO（测试用“失败即失败”）；strict=0 只计数不拦。
 * 计数见 lwp_stats.unknown_opcode / not_handshaked。 */
#define LWP_EPROTO (-71)
LWP_API int lwp_checker_enable(lwp_channel* ch, int strict);

/* ── 录制（.lwtrace，计划 §16.3）─────────────────────────────────────────────
 * 记录两个方向的每条消息（发送与接收各记一条），供 lwtrace 工具查看/回放。
 * 文件格式见 packages/lwp/README.md；同一通道重复 open 会先关闭旧文件。 */
LWP_API int lwp_trace_open(lwp_channel* ch, const char* path);
LWP_API void lwp_trace_close(lwp_channel* ch);

/* 回放：把 .lwtrace 里「发送过」的消息按原样重新入队（dir_filter < 0 表示两个方向都回放）。
 * 返回回放的条数，失败返回负错误码。计划 §16.3：壳侧事件源 → 引擎漏斗，不需要真壳。 */
LWP_API int lwp_trace_replay(lwp_channel* ch, const char* path, int dir_filter);

#ifdef LWP_TEST_HOOKS
/* 仅测试：绕过头部重算直接入队，用于构造非法头部验证接收侧校验。 */
LWP_API int lwp__test_push_raw(lwp_channel* ch, int dir, const lwp_header* hdr, const void* body, uint32_t len);
#endif

#ifdef __cplusplus
}
#endif
#endif /* LWP_H */
