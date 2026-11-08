#!/usr/bin/env python3
import sys
mp = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    f.write("package lanlu_client_next\n\n// generated from ohos/assets/test360.mp4\n")
    f.write("public let TEST_MP4: Array<UInt8> = [\n")
    for i in range(0, len(mp), 16):
        f.write("    " + ", ".join("0x%02Xu8" % b for b in mp[i:i+16]) + ",\n")
    f.write("]\n")
print("ohos_selftest_video.cj:", len(mp), "bytes")
