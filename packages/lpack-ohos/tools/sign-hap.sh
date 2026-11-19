#!/usr/bin/env bash
# 用本机已有的调试签名材料给 HAP 签名，绕开 AGC "Provision number exceeds limit" 配额。
#
# 背景：devecocli 只有在工程里没有可用 signingConfig 时才去申请新 provision；
# 配额耗尽后申请必失败。把 ~/.ohos/config 下**已存在**的材料写进 build-profile.json5，
# hvigor 的 SignHap 直接使用它，不再消耗配额。
#
# 约束：bundleName 必须与 profile 里的 bundle-name 一致——当前借用的是 CmakeHap 的
# 调试材料，所以包名是 com.example.cmakehap。配额恢复后应改用产品包 com.lanlu.clientnext
# 并重新生成 profile（届时直接跑 devecocli signature generate 即可）。
set -euo pipefail
RES=/workspace/lanlu/.research-ohos
LPACK=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD=${CN_OHOS_BUILD:-$LPACK/target/${LPACK_APP:-lanlu}}
CLT=$RES/tools/clt-7.0/command-line-tools
BP="$BUILD/target/ohos/hap/build-profile.json5"
export TMPDIR=/workspace/tmp
export JAVA_HOME=${JAVA_HOME:-/workspace/horizon-ohos/.tooling/jdk17}
export PATH=$JAVA_HOME/bin:/workspace/bin:$PATH
export DEVECO_CLI_CLT_PATH=$CLT

[ -f "$BP" ] || { echo "[FAIL] 未找到 $BP（先跑 build-ohos.sh 生成工程）"; exit 1; }

python3 - "$BP" "${OHOS_SIGN_DIR:-$HOME/.ohos/config}" <<'PY'
import sys
bp=sys.argv[1]
sign_dir=sys.argv[2]  # 绝对路径：JSON5 单引号串里不会展开 ${VAR}
block = r'''    signingConfigs: [
      {
        name: 'default',
        type: 'HarmonyOS',
        material: {
          certpath: '{sign_dir}/default_CmakeHap_X1e3XGj3W4Qqybr4NhBwXukRoG5GDSCDfamjb65g=.cer',
          keyAlias: 'debugKey',
          keyPassword: '0000001bbe8cbfb5c82abe894cde855a5124e1d04a038a7f78ade57e9b814039857c1603149e2b08f77d34',
          profile: '{sign_dir}/default_CmakeHap_X1e3XGj3W4Qqybr4NhBwXukRoG5GDSCDfamjb65g=.p7b',
          signAlg: 'SHA256withECDSA',
          storeFile: '{sign_dir}/default_CmakeHap_X1e3XGj3W4Qqybr4NhBwXukRoG5GDSCDfamjb65g=.p12',
          storePassword: '0000001bbe8cbfb5c82abe894cde855a5124e1d04a038a7f78ade57e9b814039857c1603149e2b08f77d34',
        },
      },
    ],'''
t=open(bp).read()
if "signingConfigs: []," not in t:
    # 已经注入过（上一次签名留下的）：不算错误，继续用现有配置签名
    print("signingConfigs 已存在，直接复用")
    sys.exit(0)
block = block.replace("{sign_dir}", sign_dir)
t=t.replace("signingConfigs: [],", block, 1)
open(bp,"w").write(t)
PY
echo "签名配置已注入（复用本机 CmakeHap 材料）"
cd "$BUILD/target/ohos/hap"
set +e
"$CLT/bin/hvigorw" --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap 2>&1 | tail -4
set -e
ls -l entry/build/default/outputs/default/entry-default-signed.hap | awk '{print "SIGNED_HAP=" $5}'
