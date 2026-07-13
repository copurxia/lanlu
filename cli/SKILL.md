---
name: lanlu-cli
description: "通过本 Skill 附带的 lanlu-cli 二进制调用 Lanlu 搜索、归档详情、分类查询、Source 插件搜索/下载、URL 下载、归档上传以及元数据插件执行等能力（Rust 静态编译，musl 链接，零外部依赖）。"
---

# lanlu-cli Skill

本 Skill 附带一个可执行二进制 `lanlu-cli`，通过 HTTP API 与 Lanlu 后端交互。

## 可执行文件位置

解压后会得到：

```
lanlu-cli/
├── SKILL.md
└── lanlu-cli
```

调用时请将 `lanlu-cli` 替换为 Skill 目录下的实际路径，例如：

```bash
# 项目内安装
CLI=.agents/skills/lanlu-cli/lanlu-cli

# 用户级安装
CLI=~/.agents/skills/lanlu-cli/lanlu-cli
```

## 选项

```
-o, --output <mode>       text|json|pretty-json (default: text)
    --no-proxy            忽略 http_proxy / https_proxy 环境变量
-h, --help                帮助
-V, --version             版本
```

## 环境变量

| 变量 | 必填 | 说明 |
|---|---|---|
| `LANLU_TOKEN` | 是 | Bearer Token |
| `LANLU_HOST` | 否 | 服务端地址，默认 `http://localhost:8082` |

## 命令速查

### info

```bash
$CLI info
```

### search

```bash
$CLI search [filter] [options]
```

选项：

| 选项 | 说明 |
|---|---|
| `[filter]` | 搜索过滤条件（可选），如 `"title:foo"` / `"tag:artist:bar"` |
| `-c, --category <id>` | 按分类 ID 过滤 |
| `--page <n>` | 页码 |
| `--page-size <n>` | 每页数量 |
| `--sortby <field>` | 排序字段 |
| `--order <asc\|desc>` | 排序方向 |
| `--new-only` | 仅显示新归档 |
| `--untagged-only` | 仅显示无标签归档 |
| `--favorite-only` | 仅显示收藏归档 |
| `--group-by-tanks` | 按合集分组显示 |

示例：

```bash
$CLI search "tag:artist:foo"
$CLI search --category 1 --page 1 --page-size 50
$CLI search --sortby title --order asc
$CLI search --group-by-tanks --new-only --favorite-only
```

### archive-show

```bash
$CLI archive-show <arcid> [options]
```

| 选项 | 说明 |
|---|---|
| `--include-pages` | 同时返回页面列表 |

```bash
$CLI archive-show 123
$CLI archive-show 123 --include-pages
```

### category-list

```bash
$CLI category-list
```

### cover

```bash
$CLI cover [id|--asset-id <id>]
```

| 选项 | 说明 |
|---|---|
| `[id]` | 归档或合集 ID，查询其封面 |
| `--asset-id <id>` | 已知道封面 asset_id 时直接查看 URL |

```bash
$CLI cover 123
$CLI cover --asset-id 456
```

### tankoubon-list

```bash
$CLI tankoubon-list
```

### tankoubon-show

```bash
$CLI tankoubon-show <id>
```

```bash
$CLI tankoubon-show tk_001
```

### update-metadata

```bash
$CLI update-metadata <id> [options]
```

| 选项 | 说明 |
|---|---|
| `--title <str>` | 新标题 |
| `--description <str>` | 新描述 |
| `--tags <str\|json>` | 新标签，逗号分隔或 JSON 数组 |
| `--release-at <str>` | 发布日期 |
| `--cover <id>` | 封面 asset_id |
| `--namespace <str>` | 元数据命名空间 |
| `--target-type <type>` | 目标类型：`archive`（默认）或 `tankoubon` |

```bash
$CLI update-metadata 123 --title "new title" --description "..." --tags "tag1, tag2"
$CLI update-metadata 123 --cover 456
$CLI update-metadata tk_001 --title "new" --target-type tankoubon
```

### source-list

```bash
$CLI source-list
```

### source-home

```bash
$CLI source-home <namespace>
```

```bash
$CLI source-home nhentai
```

### source-search

```bash
$CLI source-search <namespace> [query] [options]
```

| 选项 | 说明 |
|---|---|
| `[query]` | 搜索关键词（可选） |
| `--page <n>` | 页码 |
| `--filters <json>` | 筛选条件 JSON |

```bash
$CLI source-search nhentai "foo"
$CLI source-search nhentai "foo" --page 2 --filters '{"sort":"popular"}'
```

### source-filters

```bash
$CLI source-filters <namespace>
```

```bash
$CLI source-filters nhentai
```

### source-download

```bash
$CLI source-download <namespace> <remote-id> --category-id <id> [options]
```

| 选项 | 说明 |
|---|---|
| `--category-id <id>` | **必填**。目标分类 ID |
| `--kind <type>` | 条目类型，默认 `archive` |
| `--wait` | 等待任务完成 |
| `--interval <ms>` | 轮询间隔，默认 `1000` |
| `--timeout <ms>` | 超时时间，默认 `300000` |

```bash
$CLI source-download nhentai 123456 --category-id 1
$CLI source-download nhentai 123456 --category-id 1 --wait --kind archive
```

### download-url

```bash
$CLI download-url <url> --category-id <id> [options]
```

| 选项 | 说明 |
|---|---|
| `--category-id <id>` | **必填**。目标分类 ID |
| `--wait` | 等待任务完成 |
| `--interval <ms>` | 轮询间隔，默认 `1000` |
| `--timeout <ms>` | 超时时间，默认 `300000` |

```bash
$CLI download-url "https://example.com/file.zip" --category-id 1 --wait
```

注意：`--category-id` 必填，下载的文件会自动归类到指定分类。

### upload

```bash
$CLI upload <file> --category-id <id> [options]
```

| 选项 | 说明 |
|---|---|
| `--category-id <id>` | **必填**。目标分类 ID |
| `--chunk-size <bytes>` | 分片大小，默认 `8388608` (8MB) |
| `--target-type <type>` | 目标类型，默认 `archive` |
| `--overwrite` | 覆盖已存在文件 |
| `--wait` | 等待任务完成 |
| `--interval <ms>` | 轮询间隔，默认 `1000` |
| `--timeout <ms>` | 超时时间，默认 `300000` |

```bash
$CLI upload /path/to/file.zip --category-id 1 --wait
$CLI upload /path/to/file.zip --category-id 1 --overwrite --chunk-size 4194304
```

### metadata-run

```bash
$CLI metadata-run <namespace> <target-id> [options]
```

| 选项 | 说明 |
|---|---|
| `--target-type <type>` | 目标类型，默认 `archive` |
| `--param <str>` | 插件参数 |
| `--write-back` | 写回元数据 |
| `--wait` | 等待任务完成 |
| `--interval <ms>` | 轮询间隔，默认 `1000` |
| `--timeout <ms>` | 超时时间，默认 `300000` |

```bash
$CLI metadata-run ehplugin 123
$CLI metadata-run ehplugin 123 --write-back --wait
```

### task

```bash
$CLI task <id>
```

```bash
$CLI task 42
```

## 典型工作流

1. 获取分类 ID：
   ```bash
   $CLI category-list
   ```
2. 查看本地归档：
   ```bash
   $CLI search "title:some title"
   $CLI archive-show <arcid>
   ```
3. 按合集浏览：
   ```bash
   $CLI search --group-by-tanks --new-only
   $CLI tankoubon-list
   $CLI tankoubon-show <id>
   ```
4. Source 搜索并下载：
   ```bash
   $CLI source-list
   $CLI source-search nhentai "keyword"
   $CLI source-download nhentai 123456 --category-id 1 --wait
   ```
5. 运行元数据插件：
   ```bash
   $CLI metadata-run ehplugin <arcid> --write-back --wait
   ```
6. 上传本地归档：
   ```bash
   $CLI upload ./file.zip --category-id 1 --wait
   ```

## 输出格式

- `text`：人类可读的表格/摘要。
- `json`：服务端返回的原始 JSON。
- `pretty-json`：格式化后的 JSON。

```bash
$CLI -o json search "tag:foo"
$CLI -o pretty-json archive-show <arcid>
```
