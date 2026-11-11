package lwp

// LWP 协议本体（计划 §5）。本包只放**生成物 + 手写的极小辅助**，不含平台代码。
//
// 生成物（勿手改，改 IDL 后跑 python3 tools/lwp-gen.py）：
//   gen/lwp_protocol.h    C 侧结构体/opcode/枚举
//   gen/lwp_protocol.cj   仓颉侧常量 + 逐字段解码（不依赖 @C struct 布局）
//   gen/lwp_dispatch.inc  壳端分发桩
//   gen/lwp_abi.json      ABI 指纹（只允许追加）
//
// 本文件只做 re-export，让 `import lwp.*` 拿到生成类型。

// 生成物通过 include 引入（Cangjie 无 include，故生成器直接写进本包命名空间）：
// 见 gen/lwp_protocol.cj —— 生成时已声明 `package lwp`。
