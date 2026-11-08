# client-next on HarmonyOS (OHOS)

OHOS 是 client-next 的一个构建目标，**不存在独立拆分的源码工程**：业务源码只有
`client-next/src` 一份，OHOS 特有逻辑全部在 `packages/ohos`（系统层）与
本目录的构建配置里。

## 系统层职责（packages/ohos）
- ArkTS 壳：XComponent(SDL3)、窗口 id/rect、`startFilter` 注入；
- `input_filter.cpp`：窗口级鼠标/滚轮过滤器 + 原点校准 → SDL_PushEvent（对齐
  horizon-ohos 在这台设备上的已验证方案）；
- `shell_napi.cpp`：libmain.so 双角色（SDL_main + napi 模块）；
- hapgen：模板/资源/权限(INTERNET)/原生库打包、签名。

## 构建
```
client-next/ohos/build-ohos.sh
```
流程：重建结构性 shim（packages/*/native-ohos/）→ 复制 src 到 `build/ohos`
（临时产物）→ 生成 build.cj 内嵌 logo → cjpm 交叉编译 `--target
aarch64-linux-ohos` → hapgen `ui=sdl3` 签名打包。
产物：`client-next/build/ohos/target/ohos/hap/.../entry-default-signed.hap`

## 依赖
- `cjv component add stdx --toolchain sts-1.2.0-linux-x64-ohos`
- sdl3-ohos/prefix-single、ohos-stubs（含 ffmpeg/libass/freetype 链）
- CLT 7.0 SDK / JDK17 / devecocli

## 已真机验证
启动/渲染/交互、settings KV（列族+持久）、PNG/JPEG/WebP 图片、HTTP/HTTPS、
系统字体枚举、字幕探测(ffmpeg)与渲染(libass)、窗口级鼠标过滤器注册 rc=0。
未完成：真实鼠标位置实测、vlc 播放、Blitz HTML 阅读。
