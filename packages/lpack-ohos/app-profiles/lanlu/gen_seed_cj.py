#!/usr/bin/env python3
import sys
data = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    f.write("package lwindow\n\n// generated from seed kv (debug)\n")
    f.write("public let SEED_KV: Array<UInt8> = [\n")
    for i in range(0, len(data), 16):
        f.write("    " + ", ".join("0x%02Xu8" % b for b in data[i:i+16]) + ",\n")
    f.write("]\n")
print("ohos_seed.cj:", len(data), "bytes")
