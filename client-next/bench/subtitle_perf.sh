#!/usr/bin/env bash
# 字幕性能基准运行器：用真实桌面渲染链路跑通「复仇公主斯嘉丽」
# 冷扫描→播放→切换→seek→缓存命中。
# 用法：
#   LANLU_BENCH_ARCID=<arcid> ./subtitle_perf.sh [--page 6] [--play-ms 10000] ...
# 环境变量透传给客户端；输出 @@RESULT 行由本脚本收集归档到 docs/perf/。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${CLIENT_DIR}/.." && pwd)"

# 不覆盖 SDL 视频/渲染驱动：性能结果必须来自正常桌面后端，不允许默认降级到
# dummy/software。无桌面会话时直接失败，由 CI 的 smoke 测试覆盖 headless 场景。
: "${LANLU_PERF:=1}"
export LANLU_PERF=1

if [[ -z "${LANLU_BENCH_ARCID:-}" ]]; then
    echo "缺少 LANLU_BENCH_ARCID（目标档案 id）" >&2
    exit 2
fi

OUT_DIR="${REPO_DIR}/docs/perf"
mkdir -p "${OUT_DIR}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_LOG="${OUT_DIR}/subtitle-perf-${TIMESTAMP}.log"
SUMMARY_MD="${OUT_DIR}/subtitle-perf-${TIMESTAMP}.md"

echo "=== subtitle perf bench @ ${TIMESTAMP} ===" | tee "${RUN_LOG}"
echo "机器: $(uname -a)" | tee -a "${RUN_LOG}"
echo "CPU:  $(nproc) 核" | tee -a "${RUN_LOG}"
echo "内存: $(free -h 2>/dev/null | awk '/Mem/{print $2}')" | tee -a "${RUN_LOG}"
echo "ARCID: ${LANLU_BENCH_ARCID}" | tee -a "${RUN_LOG}"

echo "[build] cjpm build -V ..." | tee -a "${RUN_LOG}"
(cd "${CLIENT_DIR}" && cjpm build -V) 2>&1 | tee -a "${RUN_LOG}"

echo "[run] 启动基准 ..." | tee -a "${RUN_LOG}"
set +e
(cd "${CLIENT_DIR}" && env LANLU_PERF=1 \
    ./target/release/bin/main --subtitle-bench) 2>&1 | tee -a "${RUN_LOG}"
RC=$?
set -e
echo "[run] 退出码 ${RC}" | tee -a "${RUN_LOG}"

# 汇总 @@RESULT 行到 markdown。
{
    echo "# 字幕性能基准 ${TIMESTAMP}"
    echo ""
    echo "- 机器: $(uname -srm)"
    echo "- ARCID: ${LANLU_BENCH_ARCID}"
    echo "- 页面: ${LANLU_BENCH_PAGE:-6}"
    echo ""
    echo "## 结果"
    echo ""
    echo "| 指标 | 值 | 单位 |"
    echo "|------|----|------|"
    grep -o '@@RESULT|[^ ]*|[0-9]*|[A-Za-z]*' "${RUN_LOG}" | \
        sed 's/@@RESULT|\([^|]*\)|\([^|]*\)|\([^|]*\)/| \1 | \2 | \3 |/'
    echo ""
} > "${SUMMARY_MD}"

echo "完成。日志: ${RUN_LOG}  汇总: ${SUMMARY_MD}" | tee -a "${RUN_LOG}"
exit "${RC}"
