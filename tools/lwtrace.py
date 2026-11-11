#!/usr/bin/env python3
"""lwtrace —— 查看/统计/比较 LWP 录制文件（.lwtrace）。

计划 §16.3（调试与测试方案的核心工具）：
  * 录制：liblwp 的 lwp_trace_open(path) 把两个方向的每条消息写入 .lwtrace；
  * 查看：dump / stats / filter；
  * 回放与跨平台一致性比较：交给后续的 headless 后端（M1 后续）与 `lwtrace diff`。

文件格式（与 C 侧 trace_record 一致）：
  header : "LWPT" + u16 major + u16 minor
  record : u8 kind(0=send,1=recv) u8 dir(0=req,1=evt) u16 pad
           lwp_header{ u16 iface, u16 opcode, u32 size, u32 serial, u32 flags, u64 time_ns }
           u32 len + payload[len]
  小端；record 结构与 lwp_header 均为 packed。

用法：
  python3 tools/lwtrace.py dump  <file.lwtrace> [--iface N] [--dir event|request]
  python3 tools/lwtrace.py stats <file.lwtrace>
  python3 tools/lwtrace.py diff  <a.lwtrace> <b.lwtrace>   # 语义比较（忽略时间戳/serial）
  python3 tools/lwtrace.py verify <file.lwtrace>          # 结构完整性体检
"""

from __future__ import annotations

import argparse
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

HDR = struct.Struct("<4sHH")            # magic, major, minor
REC = struct.Struct("<BBHHHIIIQI")    # kind,dir,pad, iface,opcode,size,serial,flags,time_ns, len

KIND = {0: "send", 1: "recv"}
DIRS = {0: "request", 1: "event"}

# 由 IDL 生成，便于 dump 时显示可读名字（生成器写 lwp_abi.json）
def load_abi(root: Path) -> dict:
    path = root / "packages" / "lwp" / "abi" / "lwp_abi.json"
    if not path.exists():
        return {}
    import json
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def name_of(abi: dict, iface: int, opcode: int, direction: str) -> str:
    for iname, i in (abi.get("interfaces") or {}).items():
        if i.get("id") != iface:
            continue
        for m in i.get("messages", []):
            if m["dir"] == direction and m["opcode"] == opcode:
                return f"{iname}.{m['name']}"
    return f"iface{ iface }:{opcode}"


def read_records(path: Path):
    data = path.read_bytes()
    if len(data) < HDR.size:
        raise SystemExit(f"{path}: 文件太短")
    magic, major, minor = HDR.unpack_from(data, 0)
    if magic != b"LWPT":
        raise SystemExit(f"{path}: 不是 .lwtrace（magic={magic!r}）")
    off = HDR.size
    n = len(data)
    while off + REC.size <= n:
        (kind, d, _pad, iface, opcode, size, serial, flags, t, ln) = REC.unpack_from(data, off)
        off += REC.size
        payload = data[off:off + ln]
        off += ln
        yield dict(protocol=(major, minor), kind=kind, dir=d, iface=iface, opcode=opcode,
                   size=size, serial=serial, flags=flags, time_ns=t, payload=payload)


def cmd_dump(args) -> int:
    abi = load_abi(Path(__file__).resolve().parent.parent)
    base = None
    count = 0
    for r in read_records(Path(args.file)):
        if base is None:
            base = r["time_ns"]
        if args.dir and DIRS.get(r["dir"]) != args.dir:
            continue
        if args.iface is not None and r["iface"] != args.iface:
            continue
        t_ms = (r["time_ns"] - base) / 1e6
        print(f"{t_ms:9.3f}ms {KIND.get(r['kind'],'?'):4s} {DIRS.get(r['dir'],'?'):7s} "
              f"{name_of(abi, r['iface'], r['opcode'], DIRS.get(r['dir'],'')):24s} "
              f"serial={r['serial']:<6d} size={r['size']:<4d} flags=0x{r['flags']:x} "
              f"payload={len(r['payload'])}B")
        count += 1
    print(f"\n合计 {count} 条记录")
    return 0


def cmd_stats(args) -> int:
    abi = load_abi(Path(__file__).resolve().parent.parent)
    per = Counter()
    kinds = Counter()
    dirs = Counter()
    depth = defaultdict(int)
    max_depth = defaultdict(int)
    dropped = 0
    first = last = None
    for r in read_records(Path(args.file)):
        key = f"{KIND.get(r['kind'],'?')}:{name_of(abi, r['iface'], r['opcode'], DIRS.get(r['dir'],''))}"
        per[key] += 1
        kinds[r["kind"]] += 1
        dirs[r["dir"]] += 1
        if r["flags"] & 0x2:
            dropped += 1
        if r["kind"] == 0:
            depth[r["dir"]] += 1
            max_depth[r["dir"]] = max(max_depth[r["dir"]], depth[r["dir"]])
        else:
            depth[r["dir"]] = max(0, depth[r["dir"]] - 1)
        if first is None:
            first = r["time_ns"]
        last = r["time_ns"]

    print(f"文件：{args.file}")
    print(f"记录数：{sum(per.values())}（send={kinds[0]} recv={kinds[1]}）")
    print(f"方向：request={dirs[0]} event={dirs[1]}")
    if first is not None:
        print(f"时长：{(last-first)/1e6:.1f} ms")
    if dropped:
        print(f"可丢弃标记消息：{dropped} 条")
    for d in (0, 1):
        if max_depth[d]:
            print(f"{DIRS[d]} 最大在途：{max_depth[d]}")
    print("\n按消息统计：")
    for k, v in per.most_common():
        print(f"  {v:6d}  {k}")
    return 0


def semantic_key(r: dict) -> tuple:
    """语义键：忽略时间戳与 serial（每次运行都不同），只比“谁在什么方向发了什么”。"""
    return (r["kind"], r["dir"], r["iface"], r["opcode"], r["flags"], r["payload"])


def cmd_diff(args) -> int:
    a = list(read_records(Path(args.a)))
    b = list(read_records(Path(args.b)))
    ka = [semantic_key(r) for r in a]
    kb = [semantic_key(r) for r in b]
    if ka == kb:
        print(f"[PASS] 语义一致：{len(ka)} 条记录（{args.a} vs {args.b}）")
        return 0
    abi = load_abi(Path(__file__).resolve().parent.parent)
    print(f"[DIFF] {args.a}（{len(ka)} 条） vs {args.b}（{len(kb)} 条）")
    shown = 0
    for i in range(max(len(ka), len(kb))):
        x = ka[i] if i < len(ka) else None
        y = kb[i] if i < len(kb) else None
        if x == y:
            continue
        shown += 1
        if shown > args.max_report:
            print("  …（更多差异省略，--max-report 可调）")
            break

        def fmt(k):
            if k is None:
                return "<缺失>"
            kind, d, iface, opcode, flags, payload = k
            return (f"{KIND.get(kind,'?')} {DIRS.get(d,'?')} "
                    f"{name_of(abi, iface, opcode, DIRS.get(d,''))} flags=0x{flags:x} "
                    f"payload={len(payload)}B")

        print(f"  #{i}:")
        print(f"    A: {fmt(x)}")
        print(f"    B: {fmt(y)}")
        if x and y and x[5] != y[5]:
            print(f"    payload A 前 16B: {x[5][:16].hex()}")
            print(f"    payload B 前 16B: {y[5][:16].hex()}")
    print(f"\n[FAIL] 共 {shown} 处差异")
    return 1


def cmd_verify(args) -> int:
    """校验录制文件结构完整性（给真机拉回的现场 trace 做第一道体检）。"""
    path = Path(args.file)
    if not path.exists():
        print(f"[FAIL] 文件不存在：{path}")
        return 1
    data = path.read_bytes()
    if len(data) < HDR.size:
        print(f"[FAIL] 文件过短（{len(data)} 字节，头部需 {HDR.size}）")
        return 1
    magic, major, minor = HDR.unpack_from(data, 0)
    if magic != b"LWPT":
        print(f"[FAIL] magic 不是 LWPT：{magic!r}")
        return 1
    print(f"头部：magic=LWPT 协议 v{major}.{minor}，文件 {len(data)} 字节")
    off = HDR.size
    n = 0
    problems = []
    while off < len(data):
        if off + REC.size > len(data):
            problems.append(f"记录 #{n} 头部被截断（剩余 {len(data) - off} 字节）")
            break
        (kind, d, _pad, iface, opcode, size, serial, flags, t, ln) = REC.unpack_from(data, off)
        if kind not in (0, 1):
            problems.append(f"记录 #{n} kind={kind} 非法")
        if d not in (0, 1):
            problems.append(f"记录 #{n} dir={d} 非法")
        if ln > 4096:
            problems.append(f"记录 #{n} 载荷长度 {ln} 异常")
            break
        if off + REC.size + ln > len(data):
            problems.append(f"记录 #{n} 载荷被截断（声明 {ln}，实际 {len(data) - off - REC.size}）")
            break
        off += REC.size + ln
        n += 1
    if problems:
        for p in problems[:10]:
            print(f"  [问题] {p}")
        print(f"\n[FAIL] 共 {len(problems)} 处问题，已解析 {n} 条记录")
        return 1
    print(f"[PASS] 结构完整：{n} 条记录，无截断/越界")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="lwtrace：LWP 录制文件工具")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("dump", help="按时间顺序打印每条消息")
    d.add_argument("file")
    d.add_argument("--dir", choices=["event", "request"])
    d.add_argument("--iface", type=int)
    d.set_defaults(func=cmd_dump)
    s = sub.add_parser("stats", help="统计消息分布与在途深度")
    s.add_argument("file")
    s.set_defaults(func=cmd_stats)
    v = sub.add_parser("verify", help="校验录制文件结构（magic/记录边界/载荷长度）")
    v.add_argument("file")
    v.set_defaults(func=cmd_verify)
    d2 = sub.add_parser("diff", help="按语义比较两个录制（忽略时间戳与 serial）")
    d2.add_argument("a")
    d2.add_argument("b")
    d2.add_argument("--max-report", type=int, default=20)
    d2.set_defaults(func=cmd_diff)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
