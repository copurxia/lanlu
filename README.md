# Lanlu

兰鹿 - 基于仓颉语言的漫画归档管理系统

*Vibe Coding Warning*

| 类型 | CNB | Gitea | GitHub |
| :--: | :--: | :--: | :--: |
| 服务 | [![CNB Build](https://cnb.cool/copurx/lanlu/-/badge/git/latest/ci/status/push?branch=main)](https://cnb.cool/copurx/lanlu/-/ci) | [![Gitea Build](https://git.copur.xyz/copur/lanlu/actions/workflows/build.yaml/badge.svg?branch=main)](https://git.copur.xyz/copur/lanlu/actions/workflows/build.yaml) | [![GitHub Build](https://github.com/copurxia/lanlu/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/copurxia/lanlu/actions/workflows/build.yml) |
| 扩展 | [![CNB Build](https://cnb.cool/copurx/lanlu/-/badge/git/latest/ci/status/push?branch=main)](https://cnb.cool/copurx/lanlu/-/ci) | [![Gitea Extension](https://git.copur.xyz/copur/lanlu/actions/workflows/extension.yaml/badge.svg?branch=main)](https://git.copur.xyz/copur/lanlu/actions/workflows/extension.yaml) | [![GitHub Extension](https://github.com/copurxia/lanlu/actions/workflows/extension.yml/badge.svg?branch=main)](https://github.com/copurxia/lanlu/actions/workflows/extension.yml) |

## 简介

兰鹿是一个全栈 Web 应用，用于管理和阅读数字漫画归档。项目使用仓颉语言重新实现了 [LANraragi](https://github.com/Difegue/LANraragi) 的核心功能，并配备了现代化的前端界面。

## 功能特性

- **归档管理** - 浏览、搜索、组织漫画归档文件
- **在线阅读** - 内置阅读器，支持翻页导航
- **合集支持** - 将多个归档组织为合集（Tankoubon）
- **智能搜索** - 高级搜索和过滤功能
- **插件系统** - 可扩展的元数据和下载插件架构
- **任务管理** - 后台任务处理（扫描、下载、缩略图生成）
- **用户管理** - 多用户支持与身份认证
- **标签系统** - 完善的标签管理，支持多语言
- **系统设置** - 可配置的存储路径、扫描间隔、性能参数
- **双语界面** - 支持中文和英文

## 技术栈

### 后端

| 技术 | 说明 |
|------|------|
| 仓颉 (Cangjie) | 华为开发的现代编程语言 |
| Ignite | 仓颉 Web 框架 |
| PostgreSQL | 数据库（兼容 OpenGauss） |
| CJPM | 仓颉包管理器 |

### 前端

| 技术 | 说明 |
|------|------|
| Next.js 16 | React 框架 |
| TypeScript | 类型安全 |
| Tailwind CSS | 样式框架 |
| Radix UI | 组件库 |
| Axios | HTTP 客户端 |

## 项目结构（DDD）

```text
lanlu/
├── src/                              # 仓颉后端源码
│   ├── main.cj                       # 应用入口
│   ├── contexts/                     # 领域上下文（按业务边界拆分）
│   │   ├── archive/
│   │   │   ├── domain/               # 领域模型与领域规则
│   │   │   ├── infrastructure/       # 持久化与外部实现
│   │   │   │   └── persistence/
│   │   │   └── interfaces/           # 对外接口层
│   │   │       └── http/
│   │   ├── task/
│   │   │   ├── domain/
│   │   │   ├── application/          # 应用服务与用例编排
│   │   │   │   └── runners/          # 各类任务执行器
│   │   │   ├── infrastructure/
│   │   │   │   └── persistence/
│   │   │   └── interfaces/
│   │   │       └── http/
│   │   ├── plugin/
│   │   │   ├── domain/
│   │   │   ├── application/
│   │   │   │   └── runners/
│   │   │   ├── infrastructure/
│   │   │   │   └── persistence/
│   │   │   └── interfaces/
│   │   │       └── http/
│   │   └── asset / category / search / smart_filter / system / tag / tankoubon / user
│   ├── routes/
│   │   └── api/                      # API 路由注册
│   ├── infrastructure/               # 跨上下文基础设施
│   │   ├── archivehandler/
│   │   ├── kv/
│   │   ├── middleware/
│   │   └── migrations/
│   │       └── versions/
│   └── shared/                       # 通用配置/工具/响应视图
│       ├── config/
│       ├── utils/
│       └── views/
├── frontend/                         # Next.js 前端
│   ├── src/
│   │   ├── app/
│   │   ├── components/
│   │   ├── contexts/
│   │   ├── hooks/
│   │   ├── lib/
│   │   └── types/
│   └── messages/
├── data/                             # 运行时数据目录
│   ├── archive/
│   ├── thumb/
│   ├── plugins/
│   ├── cache/
│   └── logs/
├── docker-compose.yml
├── Dockerfile
├── cjpm.toml
└── .env.example
```

> 注：并非每个上下文都严格包含四层目录，按业务复杂度逐步演进。

## 快速开始

### 环境要求

- 仓颉 SDK (LTS 版本)
- Node.js 20+
- pnpm 10+（或使用 Corepack）
- PostgreSQL 12+
- Docker (可选)

### 构建后端

```bash
# 设置仓颉环境
source cangjie/envsetup.sh

# 构建
cjpm build -V
```

### 构建前端

```bash
cd frontend
corepack enable
pnpm install --frozen-lockfile
pnpm run build
```

### 运行

```bash
./target/release/bin/main
```

访问 `http://localhost:8082`

## Docker 部署（推荐使用 Compose）

请直接使用项目内的 `docker-compose.yml`，会同时启动：
- `lanlu`：`docker.cnb.cool/copurx/lanlu:latest`
- `postgres`：`postgres:18-alpine`

### 1. 准备数据目录

```bash
mkdir -p ./data/archive ./data/thumb ./data/logs ./data/plugins ./data/cache
```

### 2. 启动服务

```bash
docker compose pull
docker compose up -d
```

### 3. 查看状态与日志

```bash
docker compose ps
docker compose logs -f lanlu
```

### 4. 访问系统

浏览器打开：`http://localhost:8082`

### 注意事项

- 首次启动且数据库 `users` 表为空时，系统会自动创建默认管理员账号。
- 默认管理员账号和密码会写入 `./data/logs/system.log`。
- 可用以下命令快速定位默认账号密码日志：

```bash
grep -nE "已创建默认管理员账户|用户名:|密码:" ./data/logs/system.log
```

- 若数据库中已存在用户，则不会再次自动生成默认管理员账号。

## API 文档

主要 API 端点：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/info` | GET | 服务器信息 |
| `/api/search` | GET | 搜索/分页获取归档列表 |
| `/api/search/random` | GET | 随机归档 |
| `/api/archives/:id/metadata` | GET | 归档详情/元数据 |
| `/api/archives/:id/files` | GET | 归档文件列表 |
| `/api/tags` | GET | 标签列表 |
| `/api/tankoubons` | GET | 合集列表 |
| `/api/admin/plugins` | GET | 插件列表（管理员） |

### 搜索语法（`/api/search?filter=...`）

- `foo bar`：普通关键词（在标题/文件名/标签/简介中模糊匹配）
- `"foo bar"`：引号内短语匹配
- `-foo`：排除词
- `tag$`：标签完全匹配（仅匹配完整标签 token；例如 `artist:abc$` 不会命中 `artist:abcd`）
- `sortby`：支持 `created_at`、`release_at`、`updated_at`、`lastread`、`title`、`pagecount` 等；`date_added` 仍兼容但等价于 `created_at`
- `date_from` / `date_to`：日期范围会跟随当前 `sortby` 的时间字段（`created_at` / `release_at` / `updated_at`）；非时间排序时默认按 `created_at` 过滤

## 致谢

- [LANraragi](https://github.com/Difegue/LANraragi) - 原始项目
- [Ignite](https://gitcode.com/Cinexus/ignite-cangjie) - 仓颉 Web 框架
- [Radix UI](https://www.radix-ui.com/) - React 组件库

## 许可证

BSD 3-Clause License
