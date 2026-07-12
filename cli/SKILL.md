---
name: lanlu-cli
description: "通过本 Skill 附带的 scripts/lanlu-cli 脚本调用 Lanlu 搜索、归档详情、分类查询、Source 插件搜索/下载、URL 下载、归档上传以及元数据插件执行等能力（Node.js ESM 重写，无需编译，仅需 Node 18+）。"
---

# lanlu-cli Skill

本 Skill 附带一个可执行脚本 `scripts/lanlu-cli`，通过 HTTP API 与 Lanlu 后端交互。

## 前置要求

- **Node.js 18+**（内置 `fetch` 支持）
- 设置以下环境变量：

## 环境变量

| 变量 | 说明 |
|---|---|
| `LANLU_TOKEN` | **必填**。Bearer Token，用于鉴权。 |
| `LANLU_HOST` | 服务端地址，默认 `http://localhost:8082`。 |

```bash
export LANLU_TOKEN=<your-token>
export LANLU_HOST=http://localhost:8082
```

## 可执行文件位置

解压后会得到：

```
lanlu-cli/
├── SKILL.md
├── package.json
└── scripts/
    ├── lanlu-cli
    ├── main.mjs
    ├── api_client.mjs
    ├── json_utils.mjs
    ├── archive_cmds.mjs
    ├── source_cmds.mjs
    ├── task_cmds.mjs
    ├── info_cmds.mjs
    ├── cover_cmds.mjs
    ├── tankoubon_cmds.mjs
    └── poll.mjs
```

调用时请将 `lanlu-cli` 替换为 Skill 目录下的实际路径，例如：

```bash
# 项目内安装
CLI=.agents/skills/lanlu-cli/scripts/lanlu-cli

# 用户级安装
CLI=~/.agents/skills/lanlu-cli/scripts/lanlu-cli
```

## 选项

```
-o, --output <mode>       text|json|pretty-json (default: text)
    --no-proxy            忽略 http_proxy / https_proxy 环境变量
-h, --help                帮助
```

## 命令速查

### 归档 & 封面

```bash
$CLI info
$CLI search "tag:artist:foo"
$CLI search --category 1 --page 1 --page-size 50
$CLI search --group-by-tanks --new-only
$CLI archive-show <arcid>
$CLI archive-show <arcid> --include-pages
$CLI cover <arcid|tankoubon-id>
$CLI cover --asset-id 1234
```

### 分类

```bash
$CLI category-list
```

### 合集(Tankoubon)

```bash
$CLI tankoubon-list
$CLI tankoubon-show <id>
```

### Source 插件

```bash
$CLI source-list
$CLI source-home <namespace>
$CLI source-search <namespace> "keyword"
$CLI source-search <namespace> "keyword" --page 2 --filters '{"sort":"popular"}'
$CLI source-filters <namespace>
$CLI source-download <namespace> <remote-id> --category-id <id> --wait
```

### 下载与上传

```bash
$CLI download-url "https://example.com/file.zip" --category-id <id>
$CLI upload /path/to/file.zip --category-id <id> --wait

注意：`download-url` 必须指定 `--category-id`，下载的文件会自动归类到指定分类。
```

### 元数据插件

```bash
$CLI metadata-run <namespace> <arcid>
$CLI metadata-run <namespace> <arcid> --write-back --wait
```

### 元数据更新

直接修改归档或合集的标题、描述、标签等字段：

```bash
$CLI update-metadata <arcid> --title "new title" --description "..." --tags "tag1, tag2"
$CLI update-metadata <arcid> --cover 1234
$CLI update-metadata <tankoubon-id> --title "new" --target-type tankoubon
```

支持字段：`--title` `--description` `--tags` `--release-at` `--cover` `--namespace`

### 任务

```bash
$CLI task <id>
```

## 轮询选项

`source-download`、`download-url`、`upload`、`metadata-run` 支持创建任务后自动轮询（`--wait`、`--interval`、`--timeout`）。

## 封面获取说明

每个归档和合集都有一个封面图片，通过 `cover_asset_id` 或 `assets.cover` 字段关联。

- **搜索/归档详情**返回的 `cover_asset_id` 或 `assets.cover` 是一个数字 ID
- 封面图片 URL 格式：**`{LANLU_HOST}/api/assets/{asset_id}`**
- 下载方式：`GET /api/assets/{id}` 带上 Bearer Token 即可获取图片内容

```bash
# 用 curl 下载封面
curl -H "Authorization: Bearer $LANLU_TOKEN" \
  "$LANLU_HOST/api/assets/1234" -o cover.avif

# 查询归档/合集的封面 asset_id
$CLI cover <arcid>
$CLI cover --asset-id 1234
```

封面图片文件以 `.avif` 格式存储在服务器 `ASSET_PATH` 下。

## 合集(Tankoubon)说明

合集是对归档的分组管理。使用 `--group-by-tanks` 搜索时，结果中会包含 `[tank]` 开头的合集条目，显示合集的标题、归档数量和封面 asset_id。

查看合集内容：

```bash
$CLI tankoubon-list                     # 列出所有合集
$CLI tankoubon-show <tankoubon_id>       # 显示合集详情和子归档列表
$CLI search --group-by-tanks             # 搜索时按合集分组显示
$CLI archive-show <arcid>                # 查看归档所属的 tankoubon_ids
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
