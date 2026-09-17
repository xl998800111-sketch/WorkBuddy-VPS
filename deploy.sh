#!/usr/bin/env bash
# ============================================================================
#  WorkBuddy-VPS · 云端沙箱一键部署脚本
#  —— 含完整入口说明、环境探测、端口冲突解法、以及全部踩坑记录
# ============================================================================
#
#  【这个脚本做什么】
#    在 WorkBuddy 的「云端发布沙箱」里，把 workbuddy-vps 跑起来
#    （一个浏览器里的完整 Linux 中文桌面：XFCE + 中文输入法 + 开发工具链
#     + Docker-in-Docker + code-server），并让它可以通过公网地址访问。
#
# ============================================================================
#  一、先搞清楚：沙箱是什么，入口在哪
# ============================================================================
#
#  沙箱不能 SSH 进去，也没有"云端沙箱"这个按钮可以点。唯一入口是
#  WorkBuddy 的「发布为应用」（sites）能力。流程是：
#
#    ① 准备项目目录（两种方式任选）：
#       · 从仓库克隆：
#         git clone https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
#       · 或本地新建空目录，把本脚本与配套文件放进去（文件名必须叫 deploy.sh）
#    ② 把整个目录"发布"出去
#       · 如果你在对话里说"帮我部署 xxx"，背后调用的工具是 workbuddy_sites_deploy
#       · 关键参数：
#           directory : 指向该目录的绝对路径
#           language  : python（本脚本会用 python3 起代理，所以选 python）
#           startCmd  : sed -i 's/\r$//' deploy.sh; exec bash deploy.sh
#           appName   : 任意，如 "VPS 开发桌面"
#    ③ 发布成功后拿到一个形如下面的公网地址，它就是沙箱入口，
#       也是桌面最终的访问地址：
#           https://<sandbox-id>.sg.agentos-app.run
#    ④ 沙箱启动时自动执行 startCmd → 也就是本脚本 → 完成全部部署
#
#  ⚠️ startCmd 里那个 sed 不能省。Windows 上写出来的脚本是 CRLF 换行，
#     直接 bash 会报 `\r: command not found`，整个部署当场失败。
#
# ============================================================================
#  二、核心认知（这几条不知道，会白白浪费半小时）
# ============================================================================
#
#  【1】沙箱不是受限容器，它真的有 Docker。
#       工具说明里写着"只支持 Node.js / Python / Go / 静态站点"，容易让人
#       以为容器里没有 Docker。实测结果（用本脚本 --diag 可复现）：
#           docker        Docker version 27.5.1
#           compose       v2.33.0
#           用户           uid=0(root)
#           /workspace    存在
#           内存           126GB（可用 93GB）
#           磁盘           256GB（可用 254GB）
#           /dev/shm       8GB（workbuddy-vps 要 5GB，够）
#           cnb.cool       200 可达
#           镜像仓库        可达
#       那句"只支持 Node/Python/Go/静态站点"说的是【你上传的项目用什么
#       运行时来启动入口进程】，不代表容器里没有 Docker。别被误导。
#
#  【2】沙箱只对外暴露一个端口：环境变量 $PORT（实测 = 3000）。
#       · 想对外提供服务，必须监听 $PORT
#       · 而 workbuddy-vps 默认也占 3000 → 直接部署必然端口冲突
#       · 这是本次最大的坑，解法见下方「第 4 步」
#
#  【3】沙箱里的服务进程必须常驻，进程一退出沙箱就回收。
#       → 本脚本最后会 exec 一个常驻的 TCP 代理，占住 $PORT。
#
# ============================================================================
#  三、踩坑速查表
# ============================================================================
#
#  [坑 1] 以为沙箱没 Docker，直接放弃。
#         → 先跑 `bash deploy.sh --diag` 探测，用数据说话。
#
#  [坑 2] 端口冲突：workbuddy-vps 占 3000，沙箱入口也要 3000，起不来。
#         → 把容器映射改成 8080:3000（容器内仍是 3000），
#           再用 TCP 代理把沙箱的 3000 转发到 8080。
#
#  [坑 3] 网关返回 500 "socket hang up"。
#         → 不是配置错。是容器刚起、nginx 还没就绪，连接被断开。
#           用 --diag 确认容器状态是 Up，再等一会重试即可。
#
#  [坑 4] 用 HTTP 反向代理去转发桌面。
#         → 不行。KasmVNC 依赖 WebSocket，HTTP 层反代要额外处理 Upgrade
#           握手和双向流，很容易出问题。
#           本脚本用的是【纯 socket TCP 转发】——不解析 HTTP，字节级透传，
#           WebSocket 天然穿透。这是最省事也最稳的做法。
#
#  [坑 5] 首次访问看到"正在部署"页面就以为失败了。
#         → 镜像 9GB，拉取 + 解压要 3-4 分钟。脚本会输出进度，
#           期间访问看到提示页是正常的。
#
#  [坑 6] 重复执行时又 clone 一次仓库，白等几分钟。
#         → 本脚本不做任何 clone：项目文件随目录一起进沙箱，脚本与文件同目录。
#           重复执行只做 compose up，是幂等的。
#
#  [坑 7] CRLF 换行导致 `\r: command not found`。
#         → 见上面 startCmd 的 sed。
#
#  [坑 8] 沙箱休眠后再打开，短时间访问不了。
#         → 正常现象，等 30 秒左右会自动恢复。
#
# ============================================================================
#  四、用法
# ============================================================================
#
#    bash deploy.sh            # 完整部署：后台拉镜像起容器 + 前台常驻代理
#                              # （这是 startCmd 调用的模式，也是默认模式）
#    bash deploy.sh --diag     # 只做环境探测，不部署，用于确认沙箱能力
#    bash deploy.sh --setup    # 只部署，不起代理（前台跑完即退出）
#    bash deploy.sh --status   # 查看当前部署状态
#    bash deploy.sh --diag-url # 打印诊断页入口地址
#
#    部署完成后：
#      · 公网访问地址 = 你发布时拿到的那个 shareLink
#      · 用户名/密码 = 脚本自动生成并写入 .env，同时会打印出来
#      · 浏览器打开会先弹 HTTP Basic 认证框，填这组凭据
#      · 想看沙箱内部真实状态，访问 <访问地址>/__diag
#
# ============================================================================
#  五、项目里有哪些文件（完整清单）
# ============================================================================
#
#    整个项目目录随发布一起上传到沙箱，运行期【不再从任何远端拉取代码】。
#    仓库地址：https://github.com/xl998800111-sketch/WorkBuddy-VPS.git
#    目录结构：
#
#      deploy.sh              部署脚本（本文件，唯一入口）
#      docker-compose.yml     容器编排（端口映射由脚本自动改写）
#      devtop-init-fix.sh     ← 被 compose 挂载，必需
#      assets/config.toml     ← 被 compose 挂载，必需
#      README.md              项目说明
#      使用说明.md             说什么话触发部署、命令清单、注意事项
#      DEPLOY.md              通用 Docker 环境的部署指南（保留备查）
#      LICENSE                开源许可
#      .gitignore             Git 忽略规则
#      devtop-hotfix.sh       一次性运行时热修复脚本（手动执行）
#      webtop-env.md          中文输入法使用说明
#      assets/images/         README 引用的截图
#
#    注意：
#    · devtop-init-fix.sh 与 assets/config.toml 被 docker-compose.yml 以相对
#      路径挂载，缺任意一个容器都起不来，不要删。
#    · 确保 deploy.sh 是 LF 换行（从 Windows 记事本保存过的大概率是 CRLF，
#      靠 startCmd 里的 sed 兜底）。
#    · 不要在本机跑这个脚本 —— 本机没有 Docker、没有 /workspace，
#      跑了也没用。它只在沙箱里有意义。
#
# ============================================================================

set -uo pipefail

# ---------------------------- 配置区 --------------------------------------
PORT="${PORT:-3000}"                 # 沙箱对外暴露端口，由环境注入
DEVTOP_INNER_PORT=3000               # workbuddy-vps 容器内部监听的端口（固定）
DEVTOP_HOST_PORT=8080                # 映射到宿主机的端口（避开 $PORT）
WORKSPACE="${WORKSPACE_DIR:-/workspace}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"               # 项目文件与脚本同目录，随发布一起进沙箱
FALLBACK_DIR="${WORKSPACE}/workbuddy-vps"
LOG_FILE="${WORKSPACE}/devtop-deploy.log"
PROXY_PY="${WORKSPACE}/devtop-proxy.py"
CONTAINER_NAME="workbuddy-vps"

# ---------------------------- 输出样式 ------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; R=''; N=''
fi

hr()   { printf '%s\n' "------------------------------------------------------------"; }
info() { printf '%s[信息]%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s[通过]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[注意]%s %s\n' "$Y" "$N" "$*"; }
err()  { printf '%s[失败]%s %s\n' "$R" "$N" "$*"; }

# ---------------------------- 环境探测 ------------------------------------
check_env() {
  hr
  info "开始环境探测 —— 确认这个沙箱到底能不能跑 Docker 项目"
  hr

  local pass=0 fail=0

  # 1. Docker
  if command -v docker >/dev/null 2>&1; then
    ok "docker: $(docker --version 2>&1 | head -1)"
    pass=$((pass+1))
  else
    err "docker 不存在 —— 这个环境跑不了容器项目"
    fail=$((fail+1))
  fi

  # 2. Docker 守护进程
  if docker ps >/dev/null 2>&1; then
    ok "docker 守护进程: 可用"
    pass=$((pass+1))
  else
    err "docker 守护进程不可用 —— CLI 在但 daemon 没起来"
    fail=$((fail+1))
  fi

  # 3. Compose
  if docker compose version >/dev/null 2>&1; then
    ok "compose: $(docker compose version 2>&1 | head -1)"
    pass=$((pass+1))
  else
    err "docker compose 不可用"
    fail=$((fail+1))
  fi

  # 4. 权限
  if [ "$(id -u)" = "0" ]; then
    ok "权限: uid=0(root)"
    pass=$((pass+1))
  else
    warn "权限: 非 root（uid=$(id -u)），挂载 docker.sock 可能受限"
  fi

  # 5. /workspace
  if [ -d "$WORKSPACE" ]; then
    ok "$WORKSPACE: 存在"
    pass=$((pass+1))
  else
    warn "$WORKSPACE 不存在，将自动创建"
    mkdir -p "$WORKSPACE" 2>/dev/null
  fi

  # 6. 对外端口
  ok "对外端口 PORT = ${PORT}（沙箱只暴露这一个端口）"

  # 7. 内存 / 磁盘 / shm
  local mem_free disk_free shm_size
  mem_free=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
  disk_free=$(df -h "$WORKSPACE" 2>/dev/null | awk 'NR==2{print $4}')
  shm_size=$(df -h /dev/shm 2>/dev/null | awk 'NR==2{print $2}')
  [ -n "$mem_free" ]  && ok "可用内存: ${mem_free} MB"
  [ -n "$disk_free" ] && ok "可用磁盘: ${disk_free}"
  [ -n "$shm_size" ]  && ok "共享内存 /dev/shm: ${shm_size}（workbuddy-vps 需要 5GB）"

  # 8. 网络
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 https://github.com 2>/dev/null)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    ok "外网: github.com 可达（${code}）"
    pass=$((pass+1))
  else
    warn "外网: github.com 不可达，如需在沙箱内克隆仓库会失败"
  fi

  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 https://docker.cnb.cool 2>/dev/null)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    ok "镜像仓库: docker.cnb.cool 可达（${code}）"
  else
    warn "镜像仓库: docker.cnb.cool 不可达，拉镜像可能失败"
  fi

  hr
  info "探测结束：${pass} 项通过，${fail} 项失败"
  if [ "$fail" -gt 0 ]; then
    err "关键依赖缺失，部署会失败。请先解决上面的失败项。"
    return 1
  fi
  ok "环境满足部署条件，可以继续。"
  hr
  return 0
}

# ---------------------------- 写代理脚本 ----------------------------------
# 为什么需要代理：沙箱只暴露 $PORT，而 workbuddy-vps 也要 $PORT，二者冲突。
# 所以让 workbuddy-vps 容器映射到 8080，再由这个代理监听 $PORT 转发到 8080。
# 用纯 socket 转发（不解析 HTTP），WebSocket 可自然穿透 —— KasmVNC 必需。
write_proxy() {
  cat > "$PROXY_PY" << 'PYEOF'
import os, socket, threading, html, subprocess

PORT = int(os.environ.get("PORT", "3000"))
UP_HOST = "127.0.0.1"
UP_PORT = int(os.environ.get("DEVTOP_PORT", "8080"))
WORKDIR = os.environ.get("DEVTOP_WORKDIR", "/workspace/workbuddy-vps")
LOG = "/workspace/devtop-deploy.log"

def run(cmd):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=25)
        t = (p.stdout or "").strip() or (p.stderr or "").strip()
        return t or "(无输出)"
    except Exception as e:
        return "(异常: %s)" % e

def tail(path, n=30):
    try:
        with open(path, "r", errors="replace") as f:
            return "".join(f.readlines()[-n:])
    except Exception as e:
        return "(尚未生成：%s)" % e

def env_info():
    d = {}
    try:
        with open(os.path.join(WORKDIR, ".env"), "r", errors="replace") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    d[k.strip()] = v.strip()
    except Exception:
        pass
    return d

CSS = """
 *{margin:0;padding:0;box-sizing:border-box}
 body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;
      background:#f7f7f8;color:#1f2023;padding:32px 20px}
 .wrap{max-width:820px;margin:0 auto}
 h1{font-size:20px;font-weight:500;margin-bottom:8px}
 .sub{font-size:13px;color:#5f5e5a;line-height:1.7;margin-bottom:18px}
 .card{background:#fff;border:1px solid rgba(0,0,0,.08);border-radius:12px;
       padding:14px 16px;margin-bottom:12px}
 .card h2{font-size:13px;font-weight:500;margin-bottom:8px}
 .cred{font-size:14px;background:#e1f5ee;border:1px solid #9fe1cb;color:#085041;
       border-radius:10px;padding:12px 14px;margin-bottom:12px}
 .cred.muted{background:#faeeda;border-color:#fac775;color:#633806}
 pre{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:#444441;
     background:#f7f7f8;border-radius:8px;padding:10px 12px;white-space:pre-wrap;
     word-break:break-all;line-height:1.6;max-height:320px;overflow:auto}
 .bar{height:4px;background:#e6f1fb;border-radius:999px;overflow:hidden;margin-bottom:16px}
 .bar i{display:block;height:100%;width:40%;background:#378add;animation:mv 1.6s ease-in-out infinite}
 @keyframes mv{0%{margin-left:-40%}100%{margin-left:100%}}
 footer{font-size:12px;color:#b4b2a9;margin-top:16px;line-height:1.8}
"""

def render(title, sub, cred, blocks, refresh=None, bar=False):
    meta = '<meta http-equiv="refresh" content="%d">' % refresh if refresh else ""
    barh = '<div class="bar"><i></i></div>' if bar else ""
    body = "".join('<div class="card"><h2>%s</h2><pre>%s</pre></div>'
                   % (html.escape(h), html.escape(c)) for h, c in blocks)
    return """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">%s
<title>%s</title><style>%s</style></head><body><div class="wrap">
<h1>%s</h1><p class="sub">%s</p>%s%s
<footer>诊断入口 /__diag &nbsp;·&nbsp; 就绪后本页自动进入桌面。</footer>
</div></body></html>""" % (meta, html.escape(title), CSS, html.escape(title),
                           html.escape(sub), barh, cred + body)

def cred_html():
    e = env_info()
    pwd = e.get("PASSWORD", "")
    user = e.get("CUSTOM_USER", "admin")
    if pwd:
        return ('<div class="cred">用户名 <b>%s</b> &nbsp;|&nbsp; 密码 <b>%s</b></div>'
                % (html.escape(user), html.escape(pwd)))
    return '<div class="cred muted">凭据尚未生成，正在初始化…</div>'

def diag_page():
    blocks = [
        ("端口监听", run("ss -tlnp 2>/dev/null | grep -E ':%d|:%d' || echo '(无匹配)'" % (PORT, UP_PORT))),
        ("docker 容器", run("docker ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}}' 2>&1")),
        ("compose ps", run("cd %s 2>/dev/null && docker compose ps 2>&1" % WORKDIR)),
        ("端口映射配置", run("sed -n '/ports:/,+3p' %s/docker-compose.yml 2>&1" % WORKDIR)),
        ("进程", run("ps aux | grep -E 'deploy\\.sh|proxy' | grep -v grep")),
        ("镜像", run("docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>&1 | head -8")),
        ("部署日志尾部", run("tail -30 %s 2>&1" % LOG)),
    ]
    return render("VPS 诊断", "沙箱内部真实状态（容器内部执行）", cred_html(), blocks)

def send_html(conn, page):
    body = page.encode("utf-8")
    head = ("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            "Content-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" % len(body))
    try:
        conn.sendall(head.encode("utf-8") + body)
    except Exception:
        pass

def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try: s.shutdown(socket.SHUT_RDWR)
            except Exception: pass

def handle(client):
    client.settimeout(20)
    try:
        first = client.recv(16384)
    except Exception:
        first = b""
    if not first:
        try: client.close()
        except Exception: pass
        return

    if first.startswith(b"GET /__diag") or first.startswith(b"HEAD /__diag"):
        send_html(client, diag_page())
        try: client.close()
        except Exception: pass
        return

    try:
        up = socket.create_connection((UP_HOST, UP_PORT), timeout=8)
    except Exception:
        send_html(client, render(
            "WorkBuddy-VPS 正在部署",
            "镜像已拉取，容器正在启动。页面每 10 秒自动刷新，就绪后自动进入桌面。",
            cred_html(),
            [("部署日志", tail(LOG, 30))],
            refresh=10, bar=True))
        try: client.close()
        except Exception: pass
        return

    client.setblocking(True)
    up.setblocking(True)
    try:
        up.sendall(first)
    except Exception:
        pass
    t1 = threading.Thread(target=pipe, args=(client, up), daemon=True)
    t2 = threading.Thread(target=pipe, args=(up, client), daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()
    for s in (client, up):
        try: s.close()
        except Exception: pass

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(128)
    print("proxy on 0.0.0.0:%d -> %s:%d" % (PORT, UP_HOST, UP_PORT))
    while True:
        try:
            conn, _ = srv.accept()
        except Exception:
            continue
        threading.Thread(target=handle, args=(conn,), daemon=True).start()

if __name__ == "__main__":
    main()
PYEOF

  if [ -s "$PROXY_PY" ]; then
    ok "代理脚本已生成：$PROXY_PY"
  else
    err "代理脚本生成失败"
    return 1
  fi
}

# ---------------------------- 定位项目目录 --------------------------------
# 项目文件与脚本同目录，随发布一起进沙箱；运行期不拉取任何远端代码。
locate_repo() {
  if [ -f "${REPO_DIR}/docker-compose.yml" ]; then
    ok "项目目录：${REPO_DIR}"
    return 0
  fi
  if [ -f "${FALLBACK_DIR}/docker-compose.yml" ]; then
    REPO_DIR="$FALLBACK_DIR"
    warn "脚本目录缺少 docker-compose.yml，改用：${REPO_DIR}"
    return 0
  fi
  local found
  found=$(find / -maxdepth 6 -name docker-compose.yml \( -path '*vps*' -o -path '*devtop*' \) 2>/dev/null | head -1)
  if [ -n "$found" ]; then
    REPO_DIR="$(dirname "$found")"
    warn "自动定位到项目目录：${REPO_DIR}"
    return 0
  fi
  err "找不到 docker-compose.yml —— 项目文件没有随目录一起上传"
  return 1
}

# ---------------------------- 执行部署 ------------------------------------
do_deploy() {
  mkdir -p "$WORKSPACE"
  : > "$LOG_FILE"

  (
    set -x
    cd "$REPO_DIR" || exit 1

    echo "[1/4] 准备访问凭据 $(date)"
    if [ ! -f .env ]; then
      GEN_PWD=$(head -c 4096 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20)
      printf 'CUSTOM_USER=admin\nPASSWORD=%s\n' "$GEN_PWD" > .env
      chmod 600 .env
      echo "已生成 .env（随机 20 位密码）"
    else
      echo "复用已有 .env"
    fi

    echo "[2/4] 改写端口映射：宿主 ${DEVTOP_INNER_PORT} -> ${DEVTOP_HOST_PORT}"
    echo "      （原因：沙箱入口要占 ${PORT}，workbuddy-vps 默认也占 ${DEVTOP_INNER_PORT}，必须错开）"
    sed -i "s|0.0.0.0:${DEVTOP_INNER_PORT}:${DEVTOP_INNER_PORT}|0.0.0.0:${DEVTOP_HOST_PORT}:${DEVTOP_INNER_PORT}|" docker-compose.yml
    sed -i "s|0.0.0.0:3001:3001|0.0.0.0:8081:3001|" docker-compose.yml
    grep -A 3 'ports:' docker-compose.yml

    echo "[3/4] 拉取镜像并启动容器（镜像约 9GB，首次需 3-4 分钟）$(date)"
    docker compose up -d

    echo "[4/4] 部署流程结束 $(date)"
    docker compose ps
  ) >> "$LOG_FILE" 2>&1 &

  info "部署已在后台启动（日志：$LOG_FILE）"
}

# ---------------------------- 等待容器就绪 --------------------------------
wait_ready() {
  info "等待桌面服务就绪（最多 8 分钟）..."
  local i
  for i in $(seq 1 48); do
    if curl -sI --max-time 5 "http://127.0.0.1:${DEVTOP_HOST_PORT}" 2>/dev/null | grep -qE "401|200"; then
      ok "桌面服务已就绪"
      return 0
    fi
    if [ $((i % 4)) -eq 0 ]; then
      info "  仍在等待... ($((i*10))s)　$(tail -n 1 "$LOG_FILE" 2>/dev/null | cut -c1-90)"
    fi
    sleep 10
  done
  warn "等待超时。用 <访问地址>/__diag 查看沙箱内部状态，或看 $LOG_FILE"
  return 1
}

# ---------------------------- 输出部署结果 --------------------------------
show_result() {
  local user pwd
  user=$(grep -E '^CUSTOM_USER=' "${REPO_DIR}/.env" 2>/dev/null | cut -d= -f2-)
  pwd=$(grep -E '^PASSWORD=' "${REPO_DIR}/.env" 2>/dev/null | cut -d= -f2-)
  user="${user:-admin}"

  hr
  printf '%s  WorkBuddy-VPS 部署完成%s\n' "$B" "$N"
  hr
  printf '  访问地址   : %s\n' "发布时返回的 shareLink（形如 https://<sandbox-id>.sg.agentos-app.run）"
  printf '  用户名     : %s\n' "$user"
  printf '  密码       : %s\n' "${pwd:-（见 ${REPO_DIR}/.env）}"
  printf '  诊断页     : <访问地址>/__diag\n'
  printf '  容器名     : %s\n' "$CONTAINER_NAME"
  printf '  内部端口   : %s -> 容器 %s（代理：%s）\n' "$PORT" "$DEVTOP_INNER_PORT" "$DEVTOP_HOST_PORT"
  hr
  printf '  提示：首次打开约需 10-20 秒；沙箱休眠后重新打开等 30 秒。\n'
  printf '        运维命令请到 %s 下执行 docker compose ...\n' "$REPO_DIR"
  hr

  cat > "${WORKSPACE}/deploy-info.txt" << EOF
============================================================
WorkBuddy-VPS 部署信息
============================================================
访问地址 : 发布时返回的 shareLink（https://<sandbox-id>.sg.agentos-app.run）
诊断页   : <访问地址>/__diag
用户名   : ${user}
密码     : ${pwd:-（见 ${REPO_DIR}/.env）}
------------------------------------------------------------
容器名   : ${CONTAINER_NAME}
镜像     : docker.cnb.cool/fuliai/devtop/base:1.8
内部端口 : 沙箱 ${PORT} -> 代理 -> 容器 ${DEVTOP_INNER_PORT}（宿主映射 ${DEVTOP_HOST_PORT}）
仓库目录 : ${REPO_DIR}
部署日志 : ${LOG_FILE}
------------------------------------------------------------
运维命令（在 ${REPO_DIR} 下执行）:
  docker compose ps
  docker compose logs -f ${CONTAINER_NAME}
  docker compose restart ${CONTAINER_NAME}
  docker compose down && docker compose up -d
  docker exec -it ${CONTAINER_NAME} /bin/bash
============================================================
EOF
}

# ---------------------------- 状态查看 ------------------------------------
show_status() {
  hr
  info "当前部署状态"
  hr
  echo "--- 端口监听 ---"
  ss -tlnp 2>/dev/null | grep -E ":${PORT}|:${DEVTOP_HOST_PORT}|:8081" || echo "(无匹配)"
  echo
  echo "--- 容器 ---"
  docker ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}}' 2>&1 | head -10
  echo
  echo "--- 仓库 ---"
  if [ -d "${REPO_DIR}/.git" ]; then
    ok "已克隆：${REPO_DIR}"
  else
    warn "尚未克隆"
  fi
  echo
  echo "--- 凭据 ---"
  grep -E '^(CUSTOM_USER|PASSWORD)=' "${REPO_DIR}/.env" 2>/dev/null || echo "(尚未生成 .env)"
  echo
  echo "--- 日志尾部 ---"
  tail -n 15 "$LOG_FILE" 2>/dev/null || echo "(无日志)"
  hr
}

# ---------------------------- 主流程 --------------------------------------
main() {
  local mode="${1:-run}"

  printf '\n%s=== WorkBuddy-VPS 云端沙箱部署 ===%s\n\n' "$B" "$N"

  case "$mode" in
    --diag|diag)
      check_env
      exit $?
      ;;

    --status|status)
      show_status
      exit 0
      ;;

    --diag-url|diag-url)
      printf '诊断页地址：<你的访问地址>/__diag\n'
      printf '例如：https://<sandbox-id>.sg.agentos-app.run/__diag\n'
      exit 0
      ;;

    --setup|setup)
      # 只部署，不起代理（前台跑完退出）—— 用于手动调试
      check_env || exit 1
      locate_repo || exit 1
      do_deploy
      wait_ready
      show_result
      exit 0
      ;;

    run|--run|*)
      # 默认模式：startCmd 调用的就是它
      # 1) 探测  2) 后台部署  3) 【立刻】启动常驻代理，不等容器
      # 关键：代理必须立即监听 $PORT。发布方的健康检查只等 60 秒，而镜像
      # 有 9GB、要拉 3-4 分钟，等容器就绪再起代理必然超时失败。
      # 容器未就绪期间，代理会返回"正在部署"提示页 —— 这是刻意设计。
      check_env || warn "环境探测有告警，仍尝试继续部署"
      locate_repo || exit 1
      do_deploy
      write_proxy || { err "代理生成失败，无法对外提供服务"; exit 1; }

      info "启动对外代理：0.0.0.0:${PORT} -> 127.0.0.1:${DEVTOP_HOST_PORT}"
      info "容器在后台拉取镜像（约 9GB，3-4 分钟），期间访问会看到部署进度页"
      info "诊断入口：<访问地址>/__diag"
      export DEVTOP_PORT="$DEVTOP_HOST_PORT"
      export DEVTOP_WORKDIR="$REPO_DIR"
      exec python3 "$PROXY_PY"
      ;;
  esac
}

main "$@"
