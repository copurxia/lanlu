---
name: lanlu-cli
description: "Lanlu 命令行客户端使用指南：通过 lanlu-cli 调用搜索、归档详情、分类查询、Source 插件搜索/下载、URL 下载、归档上传以及元数据插件执行等能力。"
---

# lanlu-cli 使用指南

`lanlu-cli` 是 Lanlu 的命令行客户端，通过 HTTP API 与 Lanlu 后端交互。

```bash
skills/lanlu-cli/scripts/lanlu-cli <子命令> [选项]
```

## 环境变量

| 变量 | 说明 |
|---|---|
| `LANLU_TOKEN` | **必填**。Bearer Token，用于鉴权。 |
| `LANLU_HOST` | 服务端地址，默认 `http://localhost:8082`。 |

## 全局选项

```
-H, --host <url>          服务端地址
-t, --token <token>       Bearer Token
    --no-proxy            忽略 http_proxy / https_proxy 环境变量
-o, --output <mode>       text|json|pretty-json
-h, --help                帮助
```

## 命令速查

### 归档

```bash
# 搜索本地归档（filter 为空时列出全部）
lanlu-cli search "tag:artist:foo"
lanlu-cli search --category 1 --page 1 --page-size 50

# 查看归档详情
lanlu-cli archive-show <arcid>
lanlu-cli archive-show <arcid> --include-pages
```

### 分类

```bash
# 列出分类，用于获取下载/上传所需的 category_id
lanlu-cli category-list
```

### Source 插件

```bash
# 列出 Source 插件
lanlu-cli source-list

# Source 首页
lanlu-cli source-home <namespace>

# Source 搜索
lanlu-cli source-search <namespace> "keyword"
lanlu-cli source-search <namespace> "keyword" --page 2 --filters '{"sort":"popular"}'

# Source 筛选器
lanlu-cli source-filters <namespace>

# Source 下载
lanlu-cli source-download <namespace> <remote-id> --category-id <id> --wait
```

### 下载与上传

```bash
# URL 下载
lanlu-cli download-url "https://example.com/file.zip" --wait

# 上传归档
lanlu-cli upload /path/to/file.zip --category-id <id> --wait
```

### 元数据插件

```bash
# 预览模式
lanlu-cli metadata-run <namespace> <arcid>

# 写回模式
lanlu-cli metadata-run <namespace> <arcid> --write-back --wait
```

### 任务

```bash
# 查询任务详情
lanlu-cli task <id>
```

## 轮询选项

`source-download`、`download-url`、`upload`、`metadata-run` 支持创建任务后自动轮询：

```bash
--wait
--interval <ms>    # 默认 1000
--timeout <ms>     # 默认 300000
```

## 典型工作流

1. 获取分类 ID：
   ```bash
   lanlu-cli category-list
   ```
2. 查看本地是否已有目标归档：
   ```bash
   lanlu-cli search "title:some title"
   lanlu-cli archive-show <arcid>
   ```
3. 在 Source 中搜索并下载：
   ```bash
   lanlu-cli source-list
   lanlu-cli source-search nhentai "keyword"
   lanlu-cli source-download nhentai 123456 --category-id 1 --wait
   ```
4. 运行元数据插件：
   ```bash
   lanlu-cli metadata-run ehplugin <arcid> --write-back --wait
   ```
5. 上传本地归档：
   ```bash
   lanlu-cli upload ./file.zip --category-id 1 --wait
   ```

## 输出格式

- `text`：人类可读的表格/摘要。
- `json`：服务端返回的原始 JSON。
- `pretty-json`：格式化后的 JSON。

```bash
lanlu-cli -o json search "tag:foo"
lanlu-cli -o pretty-json archive-show <arcid>
```
