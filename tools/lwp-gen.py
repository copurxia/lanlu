#!/usr/bin/env python3
"""LWP 协议生成器：IDL（packages/lwp/protocol/*.toml）→ C 头 + 仓颉绑定 + 壳端分发桩 + 文档 + ABI 指纹。

计划 §5.1。生成物全部入库（packages/lwp/gen/、docs/lwp/），CI 用 --check 校验“重新生成无 diff”。

设计取舍：
  * 消息体 packed、小端；`uint32 size` 首字段；string = (u16 off, u16 len) 相对消息体起点。
  * C 侧直接用 packed struct；**仓颉侧不生成 @C struct**，而是生成「偏移常量 + 逐字段解码函数」，
    避免依赖 @C struct 的字段 ABI（仓颉里 @C struct 目前只用于不透明句柄）。
  * opcode = 同接口、同方向（request/event）的声明序号。

用法：
  python3 tools/lwp-gen.py            # 重新生成
  python3 tools/lwp-gen.py --check    # 只校验生成物是否最新（CI）
"""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IDL_DIR = ROOT / "packages" / "lwp" / "protocol"
SRC_DIR = ROOT / "packages" / "lwp" / "src"
INC_DIR = ROOT / "packages" / "lwp" / "include"
ABI_DIR = ROOT / "packages" / "lwp" / "abi"
DOC_DIR = ROOT / "docs" / "lwp"

PROTOCOL_MAJOR = 1
PROTOCOL_MINOR = 0

# type -> (C type, size, align)
SCALARS = {
    "u8": ("uint8_t", 1),
    "u16": ("uint16_t", 2),
    "u32": ("uint32_t", 4),
    "u64": ("uint64_t", 8),
    "i32": ("int32_t", 4),
    "i64": ("int64_t", 8),
    "f32": ("float", 4),
    "bool": ("uint8_t", 1),
}
STRING_SIZE = 4  # u16 off + u16 len


def camel(name: str) -> str:
    return "".join(p.capitalize() for p in name.split("_"))


def load() -> dict:
    idl = {}
    for path in sorted(IDL_DIR.glob("*.toml")):
        with path.open("rb") as f:
            data = tomllib.load(f)
        for iface_name, iface in (data.get("interface") or {}).items():
            iface["name"] = iface_name
            iface["source"] = path.name
            idl[iface_name] = iface
    return idl


def layout(msg: dict) -> list[dict]:
    """计算每条消息的字段偏移（packed，size 首字段）。"""
    offset = 4
    fields = []
    for arg in msg.get("args", []):
        t = arg["type"]
        size = STRING_SIZE if t == "string" else SCALARS[t][1]
        fields.append({"name": arg["name"], "type": t, "offset": offset, "size": size})
        offset += size
    msg["_fields"] = fields
    msg["_size"] = offset
    return fields


def message_table(idl: dict) -> list[dict]:
    """展开成 (iface, dir, opcode, msg) 列表，并分配 opcode。"""
    rows = []
    for iface_name, iface in idl.items():
        for direction in ("request", "event"):
            for opcode, msg in enumerate(iface.get(direction, [])):
                msg["iface"] = iface_name
                msg["_dir"] = 0 if direction == "request" else 1
                msg["_opcode"] = opcode
                layout(msg)
                rows.append(msg)
    return rows


def gen_header(idl: dict, rows: list[dict]) -> str:
    out = [
        "/* 由 tools/lwp-gen.py 生成，勿手改。",
        " * 源：packages/lwp/protocol/ 下的 TOML（计划 §5.1、§5.5）",
        " * 约定：packed、小端；每条消息体首字段 uint32 size（含自身，不含 lwp_header）；",
        " *       string = { uint16 off; uint16 len; }，off 相对消息体起点。",
        " */",
        "#ifndef LWP_PROTOCOL_H",
        "#define LWP_PROTOCOL_H",
        "",
        "#include <stdint.h>",
        "#include <stddef.h>",
        "",
        f"#define LWP_PROTOCOL_MAJOR {PROTOCOL_MAJOR}",
        f"#define LWP_PROTOCOL_MINOR {PROTOCOL_MINOR}",
        "",
        "/* 方向 */",
        "#define LWP_DIR_REQUEST 0",
        "#define LWP_DIR_EVENT   1",
        "",
        "typedef struct { uint16_t off; uint16_t len; } lwp_str;",
        "",
    ]
    for iface_name, iface in idl.items():
        out.append(f"/* ---- 接口 {iface_name}（version {iface.get('version', 1)}）---- */")
        out.append(f"#define LWP_IFACE_{iface_name.upper()} {iface.get('id', 0)}")
        out.append(f"#define LWP_IFACE_{iface_name.upper()}_VERSION {iface.get('version', 1)}")
        for msg in rows:
            if msg["iface"] != iface_name:
                continue
            name = msg["name"]
            macro = f"LWP_{iface_name.upper()}_{name.upper()}"
            out.append("")
            out.append(f"/* {msg.get('doc','')} */")
            out.append(f"#define {macro}_OPCODE {msg['_opcode']}")
            out.append(f"#define {macro}_SIZE {msg['_size']}")
            out.append("typedef struct __attribute__((packed)) {")
            out.append("    uint32_t size;")
            for f in msg["_fields"]:
                ctype = "lwp_str" if f["type"] == "string" else SCALARS[f["type"]][0]
                out.append(f"    {ctype} {f['name']};")
            out.append(f"}} {macro.lower()};")
        out.append("")
    out.append("#endif /* LWP_PROTOCOL_H */")
    return "\n".join(out) + "\n"


def gen_enums(enums: dict) -> tuple[str, str]:
    """返回 (C 枚举片段, 仓颉常量片段)。"""
    c_lines, cj_lines = [], []
    tables = enums
    for name, e in tables.items():
        up = name.upper()
        c_lines.append(f"/* {e.get('doc','')} */")
        for entry, value in e["entries"]:
            c_lines.append(f"#define LWP_{up}_{entry.upper()} {value}u")
        c_lines.append("")
        cj_lines.append(f"// {e.get('doc','')}")
        for entry, value in e["entries"]:
            cj_lines.append(f"public let LWP_{up}_{entry.upper()}: UInt64 = {value}")
        cj_lines.append("")
    return "\n".join(c_lines), "\n".join(cj_lines)


def gen_cangjie(idl: dict, rows: list[dict], enums: dict) -> str:
    out = [
        "// 由 tools/lwp-gen.py 生成，勿手改。",
        "// 源：packages/lwp/protocol/*.toml",
        "package lwp",
        "",
        f"public let LWP_PROTOCOL_MAJOR: UInt16 = {PROTOCOL_MAJOR}",
        f"public let LWP_PROTOCOL_MINOR: UInt16 = {PROTOCOL_MINOR}",
        "public let LWP_DIR_REQUEST: UInt16 = 0",
        "public let LWP_DIR_EVENT: UInt16 = 1",
        "",
    ]
    c_enums, cj_enums = gen_enums(enums)
    out.append(cj_enums)
    for iface_name, iface in idl.items():
        out.append(f"public let LWP_IFACE_{iface_name.upper()}: UInt16 = {iface.get('id', 0)}")
        out.append(f"public let LWP_IFACE_{iface_name.upper()}_VERSION: UInt16 = {iface.get('version', 1)}")
    out.append("")
    # 每条消息：偏移常量 + 解码函数
    for msg in rows:
        iface = msg["iface"]
        name = msg["name"]
        up = f"{iface.upper()}_{name.upper()}"
        out.append(f"public let LWP_{up}_OPCODE: UInt16 = {msg['_opcode']}")
        out.append(f"public let LWP_{up}_SIZE: Int64 = {msg['_size']}")
        out.append("")
        out.append(f"public struct Lwp{camel(iface)}{camel(name)} {{")
        for f in msg["_fields"]:
            cjtype = "String" if f["type"] == "string" else {
                "u8": "UInt8", "u16": "UInt16", "u32": "UInt32", "u64": "UInt64",
                "i32": "Int32", "i64": "Int64", "f32": "Float32", "bool": "Bool",
            }[f["type"]]
            out.append(f"    public let {f['name']}: {cjtype}")
        if msg["_fields"]:
            out.append("")
        params = ", ".join(f"{f['name']}!: {'String' if f['type']=='string' else 'PLACEHOLDER'}"
                           for f in msg["_fields"])
        # 构造函数（显式类型，按字段顺序）
        ctor_args = []
        for f in msg["_fields"]:
            t = "String" if f["type"] == "string" else {
                "u8": "UInt8", "u16": "UInt16", "u32": "UInt32", "u64": "UInt64",
                "i32": "Int32", "i64": "Int64", "f32": "Float32", "bool": "Bool",
            }[f["type"]]
            ctor_args.append(f"{f['name']}: {t}")
        out.append(f"    public init({', '.join(ctor_args)}) {{")
        for f in msg["_fields"]:
            out.append(f"        this.{f['name']} = {f['name']}")
        out.append("    }")
        out.append("}")
        out.append("")
        out.append(f"public func decodeLwp{camel(iface)}{camel(name)}(body: Array<UInt8>): Lwp{camel(iface)}{camel(name)} {{")
        if not msg["_fields"]:
            out.append(f"    return Lwp{camel(iface)}{camel(name)}()")
            out.append("}")
            out.append("")
            continue
        reads = []
        for f in msg["_fields"]:
            r = read_expr(f, "body")
            reads.append(f"        {r},")
        out.append("    return Lwp" + camel(iface) + camel(name) + "(")
        out.append("\n".join(reads))
        out.append("    )")
        out.append("}")
        out.append("")
    # 读取辅助：只生成当前 IDL 实际用到的类型，避免“未使用函数”告警
    used = {f["type"] for msg in rows for f in msg["_fields"]}
    helpers = {
        "u8": 'func lwpU8(body: Array<UInt8>, off: Int64): UInt8 { body[off] }',
        "u16": 'func lwpU16(body: Array<UInt8>, off: Int64): UInt16 {\n    UInt16(body[off]) | (UInt16(body[off + 1]) << 8)\n}',
        "u32": 'func lwpU32(body: Array<UInt8>, off: Int64): UInt32 {\n    UInt32(body[off]) | (UInt32(body[off + 1]) << 8) | (UInt32(body[off + 2]) << 16) | (UInt32(body[off + 3]) << 24)\n}',
        "u64": 'func lwpU64(body: Array<UInt8>, off: Int64): UInt64 {\n    UInt64(lwpU32(body, off)) | (UInt64(lwpU32(body, off + 4)) << 32)\n}',
        "i32": 'func lwpI32(body: Array<UInt8>, off: Int64): Int32 { Int32(lwpU32(body, off)) }',
        "i64": 'func lwpI64(body: Array<UInt8>, off: Int64): Int64 { Int64(lwpU64(body, off)) }',
        "f32": 'func lwpF32(body: Array<UInt8>, off: Int64): Float32 { Float32(lwpU32(body, off)) }',
        "bool": 'func lwpBool(body: Array<UInt8>, off: Int64): Bool { body[off] != 0 }',
        "string": '// string：u16 off + u16 len，off 相对消息体起点\n// 越界或非法 UTF-8 一律返回空串——坏消息不能把解码方打崩（协议检查器约定）。\nfunc lwpString(body: Array<UInt8>, off: Int64): String {\n    let so = Int64(lwpU16(body, off))\n    let sl = Int64(lwpU16(body, off + 2))\n    if (sl <= 0 || so + sl > body.size) { return "" }\n    try {\n        String.fromUtf8(body[so..so + sl])\n    } catch (_) {\n        ""\n    }\n}',
    }
    need = set(used)
    if "string" in need:
        need.add("u16")
    if "u64" in need or "i64" in need:
        need.add("u32")
    out.append("// ── 字节读取（小端）──────────────────────────────────────────────────────────")
    for t in ("u8", "u16", "u32", "u64", "i32", "i64", "f32", "bool", "string"):
        if t in need:
            out.append(helpers[t])
    out.append("")
    return "\n".join(out) + "\n"


def read_expr(f: dict, buf: str) -> str:
    off = str(f["offset"])
    fn = {
        "u8": "lwpU8", "u16": "lwpU16", "u32": "lwpU32", "u64": "lwpU64",
        "i32": "lwpI32", "i64": "lwpI64", "f32": "lwpF32", "bool": "lwpBool",
        "string": "lwpString",
    }[f["type"]]
    return f"{fn}({buf}, {off})"


def gen_dispatch(idl: dict, rows: list[dict]) -> str:
    out = [
        "/* 由 tools/lwp-gen.py 生成，勿手改。",
        " * 壳端分发桩：switch (iface, opcode)。未实现的消息保留 TODO，编译期可见。 */",
        "",
        "static int lwp_dispatch(lwp_channel* ch, const lwp_header* hdr, const void* body) {",
        "    switch (hdr->iface) {",
    ]
    for iface_name, iface in idl.items():
        out.append(f"    case LWP_IFACE_{iface_name.upper()}:")
        out.append("        switch (hdr->opcode) {")
        for msg in rows:
            if msg["iface"] != iface_name:
                continue
            macro = f"LWP_{iface_name.upper()}_{msg['name'].upper()}"
            out.append(f"        case {macro}_OPCODE: /* {msg.get('doc','')} */")
            out.append(f"            return lwp_handle_{iface_name}_{msg['name']}(ch, body);")
        out.append("        default: return -LWP_ERR_UNKNOWN_OPCODE;")
        out.append("        }")
    out.append("    default: return -LWP_ERR_UNKNOWN_IFACE;")
    out.append("    }")
    out.append("}")
    return "\n".join(out) + "\n"


def gen_doc(idl: dict, rows: list[dict]) -> dict[str, str]:
    docs = {}
    for iface_name, iface in idl.items():
        lines = [
            f"# 接口 `{iface_name}`（id {iface.get('id', 0)}，version {iface.get('version', 1)}）",
            "",
            "> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，"
            "因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。",
            "",
            iface.get("doc", ""),
            "",
            "由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。",
            "",
        ]
        for direction, label in (("request", "请求（引擎 → 壳）"), ("event", "事件（壳 → 引擎）")):
            msgs = iface.get(direction, [])
            if not msgs:
                continue
            lines += [f"## {label}", "",
                      "| opcode | 消息 | 方向 | since | 大小 | 字段 |",
                      "|---|---|---|---|---|---|"]
            for msg in msgs:
                fields = ", ".join(f"{f['name']}:{f['type']}@{f['offset']}" for f in msg["_fields"])
                arrow = "引擎→壳" if direction == "request" else "壳→引擎"
                lines.append(f"| {msg['_opcode']} | `{msg['name']}` | {arrow} | "
                             f"{msg.get('since',1)} | {msg['_size']} | {fields} |")
            lines.append("")
            for msg in msgs:
                if msg.get("doc"):
                    lines.append(f"- **{msg['name']}**：{msg['doc']}")
            lines.append("")
        docs[iface_name] = "\n".join(lines)
    return docs


def gen_abi(idl: dict, rows: list[dict]) -> str:
    data = {
        "protocol": {"major": PROTOCOL_MAJOR, "minor": PROTOCOL_MINOR},
        "interfaces": {},
    }
    for iface_name, iface in idl.items():
        entries = []
        for msg in rows:
            if msg["iface"] != iface_name:
                continue
            entries.append({
                "dir": "request" if msg["_dir"] == 0 else "event",
                "opcode": msg["_opcode"],
                "name": msg["name"],
                "since": msg.get("since", 1),
                "size": msg["_size"],
                "fields": [[f["name"], f["type"], f["offset"]] for f in msg["_fields"]],
            })
        data["interfaces"][iface_name] = {"id": iface.get("id", 0), "version": iface.get("version", 1), "messages": entries}
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def write(path: Path, content: str, check: bool, stale: list[str]) -> None:
    if check:
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            stale.append(str(path.relative_to(ROOT)))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def abi_breaks(old: dict, new: dict) -> list[str]:
    """检查 ABI 是否只做了「追加」：接口 id 稳定、消息不删、字段只追加。

    计划 §5.1 的硬约束：字段只允许追加；删除或改类型 = protocol_major + 1。
    """
    problems: list[str] = []
    oi = old.get("interfaces", {})
    ni = new.get("interfaces", {})
    for name, o in oi.items():
        if name not in ni:
            problems.append(f"接口被删除：{name}")
            continue
        n = ni[name]
        if o.get("id") != n.get("id"):
            problems.append(f"接口 id 变更：{name} {o.get('id')} -> {n.get('id')}")
        if n.get("version", 1) < o.get("version", 1):
            problems.append(f"接口版本回退：{name} {o.get('version')} -> {n.get('version')}")
        omsg = {(m["dir"], m["opcode"]): m for m in o.get("messages", [])}
        nmsg = {(m["dir"], m["opcode"]): m for m in n.get("messages", [])}
        for key, om in omsg.items():
            if key not in nmsg:
                problems.append(f"消息被删除：{name} {om['dir']}/{om['opcode']} {om['name']}")
                continue
            nm = nmsg[key]
            if om["name"] != nm["name"]:
                problems.append(f"消息改名（同 opcode）：{name} {om['dir']}/{om['opcode']} "
                                f"{om['name']} -> {nm['name']}")
            of = om.get("fields", [])
            nf = nm.get("fields", [])
            if len(nf) < len(of):
                problems.append(f"字段被删除：{name}.{om['name']} {len(of)} -> {len(nf)}")
            else:
                for i, (a, b) in enumerate(zip(of, nf)):
                    if a != b:
                        problems.append(f"字段被改（只允许追加）：{name}.{om['name']} "
                                        f"#{i} {a} -> {b}")
    for name in ni:
        if name not in oi:
            continue   # 新接口允许
    return problems


def cmd_check_abi(baseline_path: Path, current_path: Path) -> int:
    import json as _json
    try:
        old = _json.loads(baseline_path.read_text(encoding="utf-8"))
        new = _json.loads(current_path.read_text(encoding="utf-8"))
    except OSError as e:
        print(f"[FAIL] 读取 ABI 失败：{e}")
        return 1
    problems = abi_breaks(old, new)
    if problems:
        print(f"[FAIL] LWP ABI 出现破坏性变更（{len(problems)} 处）：")
        for p in problems[:20]:
            print("  " + p)
        print("\n提示：改协议只允许追加；删/改字段必须 protocol_major + 1 并更新基线。")
        return 1
    o_n = sum(len(i.get("messages", [])) for i in old.get("interfaces", {}).values())
    n_n = sum(len(i.get("messages", [])) for i in new.get("interfaces", {}).values())
    print(f"[PASS] LWP ABI 向后兼容（{o_n} -> {n_n} 条消息，无破坏性变更）")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="校验生成物是否最新（CI）")
    ap.add_argument("--check-abi", action="store_true",
                    help="校验 ABI 相对基线只做了追加（CI）")
    ap.add_argument("--abi-baseline", default=str(ABI_DIR / "lwp_abi.baseline.json"),
                    help="ABI 基线文件路径（默认 packages/lwp/abi/lwp_abi.baseline.json）")
    args = ap.parse_args()

    idl = load()
    if not idl:
        print("没有找到 IDL（packages/lwp/protocol/*.toml）")
        return 1
    # 顶层枚举/位域表（core.toml 里的 [enum.*] / [bitfield.*]）
    enums = {}
    for path in sorted(IDL_DIR.glob("*.toml")):
        with path.open("rb") as f:
            data = tomllib.load(f)
        for kind in ("enum", "bitfield"):
            for name, e in (data.get(kind) or {}).items():
                enums[name] = e
    rows = message_table(idl)
    stale: list[str] = []

    header = gen_header(idl, rows)
    c_enums, _ = gen_enums(enums)
    header = header.replace("#endif /* LWP_PROTOCOL_H */", c_enums + "\n#endif /* LWP_PROTOCOL_H */")

    write(INC_DIR / "lwp_protocol.h", header, args.check, stale)
    write(SRC_DIR / "lwp_gen_protocol.cj", gen_cangjie(idl, rows, enums), args.check, stale)
    write(INC_DIR / "lwp_dispatch.inc", gen_dispatch(idl, rows), args.check, stale)
    write(ABI_DIR / "lwp_abi.json", gen_abi(idl, rows), args.check, stale)
    for iface_name, text in gen_doc(idl, rows).items():
        write(DOC_DIR / f"{iface_name}.md", text, args.check, stale)

    if args.check_abi:
        return cmd_check_abi(Path(args.abi_baseline), ABI_DIR / "lwp_abi.json")

    if args.check:
        if stale:
            print("[FAIL] LWP 生成物与 IDL 不一致（先运行 python3 tools/lwp-gen.py）：")
            for s in stale:
                print("  " + s)
            return 1
        print(f"[PASS] LWP 生成物最新（{len(rows)} 条消息，{len(idl)} 个接口）")
        return 0

    print(f"生成完成：{len(rows)} 条消息，{len(idl)} 个接口 → packages/lwp/ 下的 src/include/abi 与 docs/lwp/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
