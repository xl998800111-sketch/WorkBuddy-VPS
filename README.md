# WorkBuddy-VPS

把WorkBuddy 沙箱变成中文 Linux 开发桌面** —— 一句话发布，拿到公网链接，打开就是 XFCE 桌面。

基于 [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) 架构与 `devtop/base` 镜像，针对 WorkBuddy 云端发布沙箱做了完整适配。

---### 只针对WorkBuddy国际版###---
喜欢请⭐️⭐️⭐️

## 这套版本有什么不同

本版在部署链路上做了重构，核心特点：

| 维度 | 上游版本 | 本版 |
|---|---|---|
| 代码来源 | 部署时 `git clone` 远端仓库 | **完全自包含**，所有文件随目录上传，运行期不拉取任何远端代码 |
| 部署入口 | 手动执行 `bash deploy.sh` | 通过「发布为应用」进入沙箱，脚本自动接管 |
| 端口适配 | 直接占用 3000 | **内置 TCP 代理**，解决沙箱单端口与 workbuddy-vps 默认端口冲突 |
| 环境检查 | 无 | 部署前自动探测 Docker / 权限 / 磁盘 / 网络 |
| 排障 | 翻日志 | 内置 `/__diag` 诊断页，随时查看沙箱内部真实状态 |
| 重复执行 | 可能重建容器 | **幂等**，不重建容器、不更换密码 |

---

## 快速开始

### 1. 把仓库地址发到对话里

**不用下载到本地，不用传文件** —— 直接把仓库地址发过去即可：

```
https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
```

> 帮我部署这个项目：https://github.com/xl998800111-sketch/WorkBuddy-VPS.git

接下来会克隆仓库，并把整个目录发布到云端沙箱。想一次把参数给全（少来回）：

> 帮我部署这个仓库到云端沙箱：
> https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
>
> 克隆后发布整个目录，参数如下：
> - language：`python`
> - startCmd：`sed -i 's/\r$//' deploy.sh; exec bash deploy.sh`
> - appName：`VPS 开发桌面`

### 2. 发布参数

| 参数 | 值 | 说明 |
|---|---|---|
| `directory` | 项目目录绝对路径 | 指向放 `deploy.sh` 的目录 |
| `language` | `python` | 脚本用 python3 运行代理 |
| `startCmd` | `sed -i 's/\r$//' deploy.sh; exec bash deploy.sh` | **那个 `sed` 不能省** |
| `appName` | 任意，如 `VPS 开发桌面` | 应用显示名 |

> `startCmd` 里的 `sed` 不能省 —— Windows 写出的脚本是 CRLF 换行，直接执行会报 `\r: command not found`。

### 3. 拿到链接和凭据

发布成功后你会得到一个公网地址：

```
https://<sandbox-id>.sg.agentos-app.run
```

打开它，浏览器会先弹一个认证框，填入脚本生成的用户名密码即可进入桌面。

**首次加载约需 3-4 分钟** —— 镜像有 9GB，需要拉取和解压。期间页面会显示实时进度和已生成的凭据，耐心等即可。

想自己看沙箱内部状态，访问 `<访问地址>/__diag`。

### 4. 其他部署方式

| 方式 | 适合场景 | 说明 |
|---|---|---|
| 发仓库地址 | 绝大多数情况 | 本页第 1-3 步 |
| 发本地目录 | 手上已有改过的文件 | 把文件夹绝对路径发过去，效果完全一样 |
| **手动敲命令** | 想自己控制每一步，或已经在沙箱终端里 | 见 [使用说明.md](使用说明.md) 第二节：沙箱内手动部署 / 只起容器不要代理 / 完全手工不依赖脚本 / 本地 Linux 机器 |

> ⚠️ 不要在本机执行 `deploy.sh` —— 本机通常没有 Docker 和 `/workspace`。它只在沙箱里有意义。

---

## 它是怎么跑起来的

沙箱**只对外暴露一个端口**（环境变量 `PORT`，实测为 3000），而 workbuddy-vps 默认也要占 3000 —— 直接部署必然冲突。本版用一个纯 socket 的 TCP 代理解决了这个问题：

```
浏览器
  │  https://<sandbox-id>.sg.agentos-app.run
  ▼
沙箱网关 ──► 唯一对外端口 PORT = 3000
                   │
                   ▼
        deploy.sh 内置代理（TCP 透明转发）
                   │  127.0.0.1:8080
                   ▼
            docker-proxy
                   │  0.0.0.0:8080 ──► 容器 3000
                   ▼
        ┌──────────────────────────┐
        │  workbuddy-vps 容器      │
        │  nginx + HTTP Basic 认证 │
        │  XFCE 桌面 + KasmVNC     │
        └──────────────────────────┘
```

**为什么代理必须在 TCP 层而不是 HTTP 层**：桌面基于 KasmVNC，依赖 WebSocket。HTTP 反向代理需要额外处理 Upgrade 握手和双向流，容易出问题；纯 socket 字节转发不解析 HTTP，WebSocket 天然穿透。

**为什么代理要立即启动**：发布方的健康检查只等 60 秒，而镜像要拉 3-4 分钟。所以代理必须在容器就绪前就监听 `PORT`，容器没起来时它返回"正在部署"提示页 —— 这是刻意设计。

---



### 手动命令行部署

想在终端里自己控制每一步，而不走发布流程：

```bash
cd /workspace
git clone https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
cd WorkBuddy-VPS

bash deploy.sh --diag      # 先确认环境
bash deploy.sh             # 部署（常驻前台，占住沙箱唯一对外端口，不要加 &）
```

> 注意：`bash deploy.sh` 会一直跑在前台，这是刻意设计 —— 它要在容器还没就绪时就占住 `$PORT`，否则发布方的 60 秒健康检查必然超时。

完整的手动方案（沙箱内手动 / 只起容器不要代理 / 完全手工不依赖脚本 / 本地 Linux 机器）见 [使用说明.md](使用说明.md) 第二节。

---


## 运维

在项目目录下执行：

```bash
docker compose ps                            # 查看状态
docker compose logs -f workbuddy-vps      # 实时日志
docker compose restart workbuddy-vps      # 重启
docker compose down                          # 停止
docker compose up -d                         # 启动
docker compose pull && docker compose up -d  # 更新镜像
docker exec -it workbuddy-vps /bin/bash   # 进入容器
```

部署日志写在 `/workspace/devtop-deploy.log`，代理脚本在 `/workspace/devtop-proxy.py`。

**改密码**：编辑 `.env` 里的 `PASSWORD=`，然后 `docker compose down && docker compose up -d`。

---

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| 页面一直显示"正在部署" | 正常。镜像 9GB，首次要拉 3-4 分钟，页面有实时进度 |
| 网关报 `500 socket hang up` | 容器刚起、nginx 未就绪，连接被断开。等 30 秒重试 |
| 发布时报 `port 3000 NOT listening` | 代理没能立即监听端口。检查 `startCmd` 是否完整、`deploy.sh` 是否为 LF 换行 |
| `\r: command not found` | 脚本是 CRLF 换行。`startCmd` 里的 `sed` 就是为此兜底 |
| 打开后打不开、等一会才行 | 沙箱休眠了，重新访问会唤醒，约 30 秒恢复 |
| 访问被要求登录 | 这是 HTTP Basic 认证，属预期保护。凭据见部署页面或 `.env` |
| 输入法不工作 | 桌面终端执行 `fcitx5 -d --replace` |
| 想确认沙箱能力 | 访问 `<访问地址>/__diag`，端口、容器、日志一目了然 |

---

## 安全提示

- **公开链接 = 全网可见**。本项目用 nginx HTTP Basic 认证做了保护，但请务必使用随机密码，不要改成弱口令。
- **不要把密钥、生产数据、隐私文件放进桌面**。沙箱内的数据随沙箱生命周期存在。
- 部署目录里不要放 `.env`、密钥文件 —— 它们会被一起上传。

---

## 相关文档

| 文档 | 说明 |
|---|---|
| [使用说明.md](使用说明.md) | **说什么话触发部署、手动命令行部署、命令清单、注意事项** |
| [DEPLOY.md](DEPLOY.md) | 通用 Docker 环境（本地服务器 / 自建主机）的部署指南 |
| [webtop-env.md](webtop-env.md) | 中文输入法使用说明 |

---

## License

见 [LICENSE](LICENSE)。
