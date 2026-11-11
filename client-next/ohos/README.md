# client-next 的鸿蒙（OHOS）构建入口

> 本目录现在只是一个**兼容入口**。计划
> [docs/lwindow-platform-separation-plan.md](../docs/lwindow-platform-separation-plan.md) §4.3：
> 主仓不存放鸿蒙工程与鸿蒙构建配置，它们属于 `packages/lpack-ohos`。

- 业务源码只有 `client-next/src` 一份，不含任何平台分支。
- 鸿蒙壳（ArkTS + C/C++）：[packages/lplatform-ohos](../packages/lplatform-ohos)
- 鸿蒙工程生成、打包、签名、静态门禁：[packages/lpack-ohos](../packages/lpack-ohos)
- 应用元数据（包名/版本/权限/设备）：[packages/lpack-ohos/app-profiles/lanlu/app.toml](../packages/lpack-ohos/app-profiles/lanlu/app.toml)

## 构建

```bash
# 旧入口（转发，保持兼容）
bash client-next/ohos/build-ohos.sh

# 新入口（推荐）
bash packages/lpack-ohos/tools/build-ohos.sh
```

流程：`lplatform-ohos/deps/*` 重建原生 shim → 复制 `client-next/src` 到 `client-next/build/ohos`
（临时产物，不入库）→ 生成内嵌 logo / 自检视频 → `cjpm build --target aarch64-linux-ohos`
→ 拼装模板（base + 覆盖层 + 壳源码暂存）→ hapgen 生成工程并打包 → 签名
→ 静态门禁（分层 / 依赖闭包 / 符号）。

产物：`client-next/build/ohos/target/ohos/hap/entry/build/default/outputs/default/entry-default-*.hap`

## 依赖

- 仓颉工具链（`CJV_TOOLCHAINS` 或 `CJV_OHOS_TOOLCHAIN`/`CJV_HOST_TOOLCHAIN`）
- OHOS 命令行工具（`OHOS_CLT`，或已知默认位置；见
  [packages/lplatform-ohos/deps/common-ohos.sh](../packages/lplatform-ohos/deps/common-ohos.sh)）
- hapgen：`bash packages/lpack-ohos/tools/build-hapgen.sh`
- 预编译材料（ohos-stubs、sdl3 prefix）仍在外置目录（`CN_OHOS_RES`），M0 收尾时决定去向
