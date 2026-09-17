# 部署指南 — WorkBuddy-VPS

面向**通用 Docker 环境**（本地服务器、自建主机、其他容器平台）的部署指南。

> 📌 **在 WorkBuddy 云端沙箱里部署**，请优先读 [使用说明.md](使用说明.md)：沙箱只暴露一个端口，需要脚本内置的 TCP 代理配合，直接 `docker compose up` 会端口冲突。本文件描述的是通用 Docker 环境下的流程，沙箱的差异见下方「沙箱环境额外一步」。

**仓库地址**

```
https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
```

---

## 适用场景

- **本地服务器 / 自建主机**：有 Docker，可以直接跑容器
- **其他容器环境**：任何支持 Docker 的 Linux 环境
- **WorkBuddy / CloudStudio 沙箱**：也可以，但需要额外的端口转发，见下文

## 前置条件检查

开始前先确认环境：

```bash
# 确认 Docker 可用
docker --version
docker compose version

# 确认 /workspace 目录存在（WorkBuddy 环境通常有）
ls -d /workspace 2>/dev/null

# 检测是否为 CloudStudio 沙箱环境
echo "X_IDE_SPACE_KEY=${X_IDE_SPACE_KEY:-未设置}"
```

---

## 部署流程

### 第 1 步：克隆仓库

```bash
cd /workspace
git clone https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
cd WorkBuddy-VPS
```

> 如果 `/workspace/WorkBuddy-VPS` 已存在，直接 `cd /workspace/WorkBuddy-VPS` 并 `git pull` 更新。

### 第 2 步：生成访问凭据

```bash
head -c 4096 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20 > /tmp/pwd
printf 'CUSTOM_USER=admin\nPASSWORD=%s\n' "$(cat /tmp/pwd)" > .env
chmod 600 .env
cat .env
```

### 第 3 步：启动容器

```bash
docker compose up -d
docker compose ps
```

> 首次启动要拉取约 **9GB** 镜像，耗时 3-4 分钟属正常。用 `docker compose logs -f workbuddy-vps` 看进度。

### 第 4 步：访问

| 环境 | 访问地址 |
|---|---|
| 本地机器 | `http://localhost:3000` |
| 本地服务器 / 自建主机 | `http://<服务器IP>:3000` |

浏览器会先弹 HTTP Basic 认证框：用户名 `admin`，密码是 `.env` 里的 `PASSWORD`。

### 沙箱环境额外一步

如果 `$X_IDE_SPACE_KEY` 存在，说明是 CloudStudio 沙箱 —— 沙箱**只对外暴露 `$PORT` 一个端口**，容器不能再绑 3000。要先改映射，再把 `$PORT` 转发到新端口：

```bash
# 容器内部仍是 3000，映射到宿主机 8080，避开沙箱的 $PORT
sed -i "s|0.0.0.0:3000:3000|0.0.0.0:8080:3000|" docker-compose.yml
sed -i "s|0.0.0.0:3001:3001|0.0.0.0:8081:3001|" docker-compose.yml
docker compose up -d

# 纯 TCP 转发。桌面基于 KasmVNC，依赖 WebSocket，不能用 HTTP 反代
socat TCP-LISTEN:${PORT:-3000},fork,reuseaddr TCP:127.0.0.1:8080
```

> 更省事的做法：直接在项目目录跑 `bash deploy.sh`，上述端口改写与转发它都做完了。完整说明见 [使用说明.md](使用说明.md) 第二节。

---

## 环境说明

| 环境 | 检测条件 | 访问方式 |
|---|---|---|
| 本地服务器 / 自建主机 | 无 `X_IDE_SPACE_KEY` | `http://<服务器IP>:3000` |
| CloudStudio 沙箱 | `$X_IDE_SPACE_KEY` 存在 | 发布时返回的 `https://<sandbox-id>.sg.agentos-app.run`，需配合 TCP 转发 |

## 密码说明

- 首次部署时生成 **20 位随机密码**，存储在 `.env` 文件中
- 后续重启容器会复用同一密码，不会每次都变
- 如需重新生成密码：删除 `.env` 文件，重新执行第 2 步
- 如需手动指定密码：编辑 `.env` 文件中的 `PASSWORD=xxx`，然后 `docker compose down && docker compose up -d`
- 用 `bash deploy.sh` 部署时，脚本会把访问地址、用户名、密码和运维命令汇总写到 `/workspace/deploy-info.txt`，方便随时查阅

## 环境要求

| 项目 | 要求 |
|---|---|
| Docker | 20+ |
| Docker Compose | v2+ |
| 内存 | 4GB（推荐 8GB） |
| 磁盘 | 10GB+ 可用空间 |
| 端口 | 3000（HTTP）、3001（HTTPS）可用 |

## 常见问题处理

### 端口被占用

```bash
# 查看占用 3000 端口的容器
docker ps --filter publish=3000
# 清掉旧容器后重试
docker rm -f workbuddy-vps
```

### 容器启动后无法访问

```bash
# 检查容器状态
docker compose ps
# 查看日志
docker compose logs --since 10m workbuddy-vps
# 确认端口绑定是 0.0.0.0:3000:3000（不能是 127.0.0.1）
grep -A 3 'ports:' docker-compose.yml
```

### CloudStudio 沙箱中无法访问

沙箱只暴露一个端口，容器不能直接绑 3000。按上面「沙箱环境额外一步」改写端口映射并加 TCP 转发。

### 修改密码

编辑 `.env` 文件中的 `PASSWORD` 变量，然后：

```bash
docker compose down && docker compose up -d
```

## 运维命令速查

```bash
docker compose ps                              # 查看状态
docker compose logs -f workbuddy-vps           # 实时日志
docker compose restart workbuddy-vps           # 重启
docker compose down                            # 停止
docker compose up -d                           # 启动（需先有 .env）
docker exec -it workbuddy-vps /bin/bash        # 进入容器
docker compose pull && docker compose up -d    # 更新镜像
```
