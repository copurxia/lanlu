# Lanlu

兰鹿 - 基于仓颉语言的漫画归档管理系统

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
| CJoy | 仓颉 Web 框架 |
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

## 项目结构

```
lrr4cj/
├── src/                    # 仓颉后端源码
│   ├── main.cj            # 应用入口
│   ├── controllers/       # 控制器
│   ├── services/          # 业务逻辑
│   ├── dao/               # 数据访问层
│   ├── models/            # 数据模型
│   ├── routes/            # 路由定义
│   └── utils/             # 工具函数
├── frontend/              # Next.js 前端
│   ├── src/
│   │   ├── app/          # 页面路由
│   │   ├── components/   # React 组件
│   │   ├── lib/          # 服务和工具
│   │   ├── contexts/     # React Context
│   │   └── types/        # TypeScript 类型
│   └── messages/         # 国际化文件
├── plugins/               # 插件目录
│   ├── Download/         # 下载插件
│   ├── Login/            # 登录插件
│   └── Metadata/         # 元数据插件
├── data/                  # 运行时数据
│   ├── archive/          # 归档存储
│   ├── thumb/            # 缩略图缓存
│   └── logs/             # 日志文件
├── cjpm.toml             # 仓颉包配置
├── .env.example          # 环境变量模板
└── Dockerfile            # Docker 配置
```

## 快速开始

### 环境要求

- 仓颉 SDK (LTS 版本)
- Node.js 18+
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
npm install
npm run build
```

### 运行

```bash
./target/release/bin/main
```

访问 `http://localhost:8082`

## Docker 部署

```bash
# 构建镜像
docker build -t lrr4cj:latest .

# 运行容器
docker run -d \
  -p 8082:8082 \
  -e DB_STRING=postgres://user:password@postgres:5432/lanlu?sslmode=disable \
  -e JWT_SECRET=d2015833994569e3a4e3 \
  -e CORS_ORIGIN=* \
  -v /path/to/archives:/app/data/archive \
  lrr4cj:latest
```

## API 文档

主要 API 端点：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/info` | GET | 服务器信息 |
| `/api/archives` | GET | 归档列表 |
| `/api/archives/:id` | GET | 归档详情 |
| `/api/archives/:id/files` | GET | 归档文件列表 |
| `/api/archives/:id/thumbnail` | GET | 归档缩略图 |
| `/api/search` | GET | 搜索归档 |
| `/api/tags` | GET | 标签列表 |
| `/api/tankoubons` | GET | 合集列表 |
| `/api/plugins` | GET | 插件列表 |

## 致谢

- [LANraragi](https://github.com/Difegue/LANraragi) - 原始项目
- [CJoy](https://gitcode.com/Cangjie-SIG/cjoy) - 仓颉 Web 框架
- [Radix UI](https://www.radix-ui.com/) - React 组件库

## 许可证

MIT License
