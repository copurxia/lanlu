# lanlu-mcp

Lanlu 的 [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) 服务器实现，通过 stdio JSON-RPC 与 Lanlu 后端 HTTP API 通信。

## 构建

需要 Rust 工具链。推荐静态 musl 构建：

```bash
rustup target add x86_64-unknown-linux-musl
cd mcp
CC_x86_64_unknown_linux_musl=musl-gcc \
  cargo build --release --target x86_64-unknown-linux-musl
```

产物：`target/x86_64-unknown-linux-musl/release/lanlu-mcp`

## 环境变量

| 变量 | 必填 | 说明 |
|---|---|---|
| `LANLU_TOKEN` | 是 | Bearer Token |
| `LANLU_HOST` | 否 | 服务端地址，默认 `http://localhost:8082` |
| `LANLU_NO_PROXY` | 否 | 设置后忽略 http_proxy / https_proxy |

## 客户端配置

### ZCode / Claude Desktop / Cursor

```json
{
  "mcpServers": {
    "lanlu": {
      "command": "/path/to/lanlu-mcp",
      "env": {
        "LANLU_TOKEN": "your-token",
        "LANLU_HOST": "http://localhost:8082"
      }
    }
  }
}
```

## 可用 Tools

| Tool | 说明 |
|---|---|
| `lanlu_info` | 服务器信息 |
| `lanlu_search` | 搜索归档 |
| `lanlu_archive_show` | 归档详情 |
| `lanlu_category_list` | 分类列表 |
| `lanlu_cover` | 封面信息 |
| `lanlu_tankoubon_list` | 合集列表 |
| `lanlu_tankoubon_show` | 合集详情 |
| `lanlu_update_metadata` | 更新元数据 |
| `lanlu_source_list` | Source 插件列表 |
| `lanlu_source_home` | Source 主页 |
| `lanlu_source_search` | Source 搜索 |
| `lanlu_source_filters` | Source 筛选器 |
| `lanlu_source_download` | Source 下载 |
| `lanlu_download_url` | URL 下载 |
| `lanlu_upload` | 上传本地文件 |
| `lanlu_metadata_run` | 运行元数据插件 |
| `lanlu_task` | 任务状态 |

每个 tool 的参数定义可通过 MCP `tools/list` 获取。

## 手动测试

```bash
LANLU_TOKEN=xxx LANLU_HOST=http://localhost:8082 ./target/release/lanlu-mcp <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test"}}}
{"jsonrpc":"2.0","method":"initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
EOF
```

## 协议

- 传输：stdio，每行一个 JSON-RPC 2.0 消息
- 支持方法：`initialize`、`initialized`、`tools/list`、`tools/call`
- 支持通知：`notifications/cancelled`（携带 `requestId`，可中断正在执行的 `tools/call`，被取消的请求返回错误码 `-32800`）
- 请求并发：每个带 id 的请求在独立任务中执行，慢调用（如长轮询任务）不会阻塞后续请求读取
- 返回内容类型：text（JSON 字符串）
