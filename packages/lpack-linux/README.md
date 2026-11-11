# lpack-linux —— Linux 打包（平台包）

计划：[docs/lwindow-platform-separation-plan.md](../../docs/lwindow-platform-separation-plan.md) §4.4、§9.4。

**状态：可用（2026-11-11 落地）。** `tools/build-deb.sh` 负责全部打包，
CI 只调用它；本机可用 `--self-test` 验证脚本本身（不需要引擎产物）。

```bash
bash packages/lpack-linux/tools/build-deb.sh --self-test          # 自检
bash packages/lpack-linux/tools/build-deb.sh \
  --binary target/release/bin/main --icon assets/lanlu_logo_gold.png --out dist
```

已实现：非系统库捆绑（`/usr`、`/lib`、`/lib64` 靠 `Depends` 声明，不打进包）、
`/opt/<pkg>` + `/usr/bin` wrapper（设 `LD_LIBRARY_PATH`）、`.desktop`
（`StartupWMClass=lanlu` 与壳的 app_id 一致）、hicolor 图标、仓颉运行时兜底（`CANGJIE_HOME`）。

## 职责

把 Wayland 壳可执行文件 + 引擎 + 运行库打成 `.deb`：

```
/usr/bin/lanlu                                   （lplatform-wayland 产物）
/usr/lib/lanlu/liblanlu_engine*.so               （client-next 交叉/本机编译产物）
/usr/lib/lanlu/liblwp.so                         （协议通道）
/usr/lib/lanlu/libcangjie-*.so                   （仓颉运行时）
/usr/lib/lanlu/<业务原生依赖>
/usr/share/applications/lanlu.desktop            StartupWMClass=lanlu（与 set_app_id 一致）
/usr/share/icons/hicolor/...                     hicolor 图标
```

`Depends:` 至少包含 `libwayland-client0, libxkbcommon0, libvulkan1`。

## 迁移来源

现在这些步骤内联在 `.github/workflows/client-next.yml` 的 build-test job 里
（`verify in-repository dependencies` → `dpkg-deb --build` → 上传 `dist/*.deb`），
M3W 迁入本包，CI 只调用脚本。
