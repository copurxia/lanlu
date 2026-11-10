# 在具备 MSYS2（mingw-w64-x86_64-rocksdb）的 Windows 环境执行 rocksdb_ffi 最小 FFI 测试。
# 用途：完成 todo.md §4.6「Linux/Windows 均运行最小 FFI 测试」的 Windows 侧验证。
# 前置：Cangjie 1.1.3（cjpm 在 PATH）；MSYS2 MINGW64 安装
#       mingw-w64-x86_64-toolchain 与 mingw-w64-x86_64-rocksdb（mingw64/bin 与 mingw64/lib 在 PATH）。
# 用法：powershell -ExecutionPolicy Bypass -File packages/rocksdb_ffi/scripts/verify-windows.ps1
# 期望输出末尾：PASS: rocksdb_ffi Windows FFI 测试全部通过
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot   # packages/rocksdb_ffi

Write-Host "==> 1/3 检查工具链"
if (-not (Get-Command cjpm -ErrorAction SilentlyContinue)) {
    throw "未找到 cjpm，请先安装 Cangjie 1.1.3 并加入 PATH"
}
cjpm --version

Write-Host "==> 2/3 编译版本探测 bridge（x86_64-w64-mingw32-g++，读 rocksdb/version.h 宏）"
$bridgeDir = Join-Path $root "native"
& x86_64-w64-mingw32-g++ -std=c++17 -Wall -Wextra -Werror -O2 -c `
    (Join-Path $bridgeDir "lanlu_rocksdb_bridge.c") -o (Join-Path $bridgeDir "lanlu_rocksdb_bridge.o")
if ($LASTEXITCODE -ne 0) { throw "bridge 编译失败：需 MSYS2 的 mingw-w64-x86_64-toolchain（含 g++）" }
& ar rcs (Join-Path $bridgeDir "liblanlu_rocksdb_bridge.a") (Join-Path $bridgeDir "lanlu_rocksdb_bridge.o")
if ($LASTEXITCODE -ne 0) { throw "ar 打包失败" }

Write-Host "==> 3/3 运行 cjpm test（版本门槛/byte 边界/CF/快照/事务 rollback/多线程用例）"
Push-Location $root
try {
    cjpm test
    if ($LASTEXITCODE -ne 0) { throw "cjpm test 未全绿（见上方输出）" }
} finally {
    Pop-Location
}
Write-Host "PASS: rocksdb_ffi Windows FFI 测试全部通过"
Write-Host "请将上方完整输出回贴，用于勾选 todo.md §4.6。"
