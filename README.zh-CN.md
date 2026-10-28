# magpie-workspace

[English](README.md) | [简体中文](README.zh-CN.md)

**每个开发者一个隔离的 Claude Code 工作区，每个工作区一个独立的 Magpie 网关。**

这是一个可自托管的最小参考实现：Claude Code 运行在独立 Docker 工作区里，模型请求先到同工作区内的 Magpie 网关，再到上游 Provider。请求从工作区/服务器发出，而不是从开发者笔记本或一个共享中转站发出。每个 workspace 有独立的 home 卷、Claude 配置、Magpie 配置、web key 和 gateway key。

> 这是一个隔离与部署方案，**不保证账号不会被风控**。请遵守 Provider 的服务条款，不要用它共享账号、转售访问或绕过限额。

---

## 解决的问题

Claude Code 订阅通常是个人账号。多人共用一个中转站、一个 API Key 或一个出口 IP 时，Provider 会看到混乱的会话、IP、机器和额度使用，账号容易被认为是共享/异常。传统中转站还有：

- 所有人共用一个凭据池；
- 所有人共用一个出口 IP；
- 跨用户的请求日志和数据；
- 额度互相挤占；
- 中央服务单点故障。

## 方案

```text
开发者浏览器 / VS Code
          |
          | HTTPS（Coder path app，可选 Coder 登录）
          v
+---------------------------------------------------+
|  Coder workspace（每人一个 Docker 容器）           |
|                                                   |
|  Chromium + noVNC          Claude Code            |
|       :6080                 |                     |
|                             | shim                 |
|                             v                     |
|                   CLAUDE_CODE_ENTRYPOINT=custom   |
|                             |                     |
|                             v                     |
|            Magpie gateway 127.0.0.1:3425          |
|                             |                     |
|            Magpie web/API   :3430                 |
|            nginx path proxy :3440                 |
+-----------------------------|---------------------+
                              |
                              v
                    upstream provider APIs
```

- **接近本地的开发体验**：浏览器桌面、终端、VS Code Remote-SSH。
- **远程发起请求**：Claude Code 和 Magpie 都在 workspace 内，请求从服务器/工作区发出，不是从本机发出。
- **每 workspace 独立网关**：没有共享 Magpie 中转，没有共享 Provider 配置，没有跨用户日志。
- **独立环境**：独立容器、home 卷、Claude 配置、Magpie 凭据和 key。
- **不共享账号**：每个人登录自己的 Provider 账号，自己保存凭据。

## 特性

- Coder 控制面 + Docker 工作区。
- 每个开发者一个隔离 workspace，默认 1 CPU / 2 GiB，可配置。
- 工作区内置最新 Claude Code。
- `claude` shim：先 `export CLAUDE_CODE_ENTRYPOINT=custom`，再执行 `/usr/local/bin/claude-real`。
- 每 workspace 独立 Magpie Web UI + Gateway，配置持久化。
- workspace 内 nginx 适配 Coder path app。
- Magpie App 支持 owner / authenticated / public 三种共享级别。
- Chromium + noVNC + 剪贴板桥。
- `/home/coder` 和 `/home/coder/workspace` 独立持久卷。
- Docker Compose + Makefile 快速启动。
- 可选 Mutagen 本地目录同步脚本。

## 环境要求

- Linux 主机，Docker Engine + Docker Compose v2。
- 操作机安装 Coder CLI（推送模板/创建 workspace）。
- 生产环境建议有域名和 TLS 反向代理。
- 小规模测试：4 GiB 内存 / 2 vCPU；多工作区按 **每 workspace 2 GiB + 1 vCPU** 预留。

## 快速开始

### 1. 克隆并配置

```bash
git clone https://github.com/<your-account>/magpie-workspace.git
cd magpie-workspace
cp .env.example .env
$EDITOR .env
```

至少设置：

```dotenv
POSTGRES_PASSWORD=...
CODER_ACCESS_URL=http://localhost:7080
CODER_ADMIN_USER=admin
CODER_ADMIN_EMAIL=admin@example.com
CODER_ADMIN_PASSWORD=...
```

生产环境设置 `CODER_ACCESS_URL=https://coder.example.com`，并在前面放 TLS 反向代理。

### 2. 启动 Coder 并创建管理员

```bash
make up
make admin
```

### 3. 安装 Coder CLI 并登录

```bash
brew install coder        # macOS
# 或 Linux: curl -fsSL https://coder.com/install.sh | sh

coder login http://localhost:7080
# 或 coder login https://coder.example.com
```

### 4. 构建镜像并推送模板

```bash
make image
make template
```

`make image` 会拉取最新 Magpie、安装最新 Claude Code、创建 `claude-real` 和 shim。

### 5. 创建用户和 workspace

```bash
make user USER=alice EMAIL=alice@example.com
make workspace SPEC=alice/dev
```

`make user` 会交互式输入密码；新用户创建后会被激活。

打开 Coder，启动 `alice/dev`，进入 **Magpie** App。workspace metadata 里有：

- `magpie_url`：带 key 的 Web UI 地址；
- `magpie_gateway_url`：`https://<coder-host>/@alice/dev.main/apps/magpie/v1`；
- `magpie_gateway_key`：网关 key。

Web 地址形如：

```text
https://coder.example.com/@alice/dev.main/apps/magpie/?k=magpie-alice-dev-web
```

Gateway：

```text
Base URL: https://coder.example.com/@alice/dev.main/apps/magpie/v1
API Key:  magpie-alice-dev-gw
```

不带 `?k=` 会返回 401，这是正常的。

### 6. 使用

- 终端：Coder Web Terminal 或 `coder ssh alice/dev`。
- 浏览器桌面：Browser App。
- VS Code：`coder config-ssh`，连接 `alice-dev.coder`，打开 `/home/coder/workspace`。

## Magpie 使用

1. 打开 metadata 里的 keyed `magpie_url`。
2. 在 Magpie UI 添加 Provider 或登录订阅账号。
3. 给外部客户端创建 Gateway Key。
4. 外部客户端使用 `magpie_gateway_url` + `magpie_gateway_key`。
5. workspace 内 Claude Code 可用 Magpie Agents 页面或 CLI 接入。

检查：

```bash
magpie --version
magpie gateway-key list
cat ~/.config/magpie/coder-gateway-key
```

## 公开访问（可选）

默认 `template/main.tf`：

```hcl
variable "magpie_share" {
  default = "owner"
}
```

即 Magpie path app 需要 Coder 登录。这是安全默认值。

如果希望不登录 Coder 也能访问 keyed URL：

1. 把 `template/main.tf` 的默认值改成 `"public"`；
2. `.env` 设置 `CODER_ALLOW_PUBLIC_PATH_APPS=true`；
3. `docker compose up -d` 重建 Coder，再 `make template`；
4. 更新/重建 workspace。

公开 path app 可能以 workspace owner 身份访问 Coder API，启用前请阅读 [`docs/security.md`](docs/security.md)。

## 隔离模型

| 资源 | 隔离方式 |
|---|---|
| workspace 容器 | 每个用户/workspace 独立 |
| `/home/coder` | 独立 Docker volume |
| `/home/coder/workspace` | 独立 Docker volume |
| Claude 配置 | workspace 内 `CLAUDE_CONFIG_DIR` |
| Magpie 配置/key | workspace 内 `~/.config/magpie` |
| Chromium profile | workspace 内 |
| Provider 账号 | 每个人自己的账号 |

Coder 控制面和 Docker 主机是共享基础设施；如果主机被攻破，workspace 隔离不能当作安全边界。

## 运维

```bash
make logs       # 查看 Coder 日志
make down       # 停止，保留卷
make clean      # 停止并删除卷（危险）
```

升级：`make image` 后，新 workspace 使用最新镜像；已有 workspace 需要 stop/start 或 update。

## 文件同步 / 编辑器

- Coder Desktop File Sync
- `rsync` / `scp`
- 可选 `scripts/coder-sync.sh`（Mutagen）
- VS Code Remote-SSH

## 故障排查

- Magpie 只显示骨架：用 keyed URL，强制刷新，确认 workspace 使用最新镜像。
- 401：缺少 `?k=` 或 key 不对。
- Coder App 502：检查 `docker compose ps`、Coder 日志、workspace health。
- 模板推送失败：先 `coder login`，确认 CLI 指向同一 Coder。
- 镜像里没有 `claude`：重新 `make image`。

更多见 [`docs/troubleshooting.md`](docs/troubleshooting.md)。

## 目录结构

```text
.
├── docker-compose.yml
├── .env.example
├── Makefile
├── scripts/
├── template/main.tf
├── workspace/
└── docs/
```

## License

MIT。Coder 是 AGPL-3.0，Magpie 是 MIT；本项目只拉取官方镜像，不 vendor 它们的源码。见 [`NOTICE`](NOTICE)。
