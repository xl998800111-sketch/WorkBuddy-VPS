#!/usr/bin/with-contenv bash
# devtop-init-fix.sh
# CloudStudio 沙箱环境兼容修复脚本
# 通过 linuxserver /custom-cont-init.d/ 机制在容器启动时自动执行
# 在其他平台运行为 no-op，不影响正常行为

set -e

echo "[devtop-init-fix] 开始环境兼容修复..."

# ========== 修复 1: dockremap 用户名冲突 ==========
# CloudStudio 宿主启用了 Docker userns-remap，会在容器 /etc/passwd 注入
# dockremap:x:1000:1000，与镜像的 aican.do:x:1000:1000 冲突，
# 导致 ls 等命令显示属主为 dockremap 而非 aican.do。
# 其他平台无此问题，此操作为 no-op。

if grep -q "^dockremap:x:1000:" /etc/passwd 2>/dev/null; then
    echo "[devtop-init-fix] 检测到 dockremap 用户冲突，移除..."
    sed -i '/^dockremap:x:1000:/d' /etc/passwd
    sed -i '/^dockremap:x:1000:/d' /etc/group
    echo "[devtop-init-fix] dockremap 已移除，aican.do 现在是唯一的 uid=1000 用户"
fi

# ========== 修复 2: .zshrc 和 oh-my-zsh 初始化 ==========
# 在某些环境下（如 /config 首次挂载空目录），zsh 可能在默认配置复制完成前
# 首次启动，自动生成空的 .zshrc（仅含 "# Created by newuser"），
# 覆盖了镜像应有的完整配置。

ZSHRC_FILE="/config/.zshrc"
DEFAULT_ZSHRC="/defaults/devtop-config/.zshrc"

# 检查 .zshrc 是否缺失或为空壳（少于 10 行说明是 newuser 自动生成的）
if [ ! -f "$ZSHRC_FILE" ] || [ "$(wc -l < "$ZSHRC_FILE")" -lt 10 ]; then
    echo "[devtop-init-fix] .zshrc 缺失或不完整，从默认配置恢复..."
    if [ -f "$DEFAULT_ZSHRC" ]; then
        cp "$DEFAULT_ZSHRC" "$ZSHRC_FILE"
        chown 1000:1000 "$ZSHRC_FILE"
        echo "[devtop-init-fix] .zshrc 已恢复 ($(wc -l < "$ZSHRC_FILE") 行)"
    fi
fi

# 检查 oh-my-zsh 是否存在
if [ ! -d "/config/.oh-my-zsh" ]; then
    echo "[devtop-init-fix] oh-my-zsh 缺失，从 root 复制..."
    if [ -d "/root/.oh-my-zsh" ]; then
        cp -a /root/.oh-my-zsh /config/.oh-my-zsh
        mkdir -p /config/.oh-my-zsh/completions
        chown -R 1000:1000 /config/.oh-my-zsh
        echo "[devtop-init-fix] oh-my-zsh 已复制到 /config/"
    fi
fi

# 确保 completions 目录存在
mkdir -p /config/.oh-my-zsh/completions 2>/dev/null || true
chown -R 1000:1000 /config/.oh-my-zsh 2>/dev/null || true

# ========== 修复 3: hardinfo2 缺失依赖安装 ==========
# hardinfo2（硬件信息）依赖 mesa-utils（glxinfo）和 dmidecode 来获取完整系统信息。
# 镜像未预装这些可选依赖，导致 GUI 弹出"未正确打包"警告。
# 注意：dmidecode 在容器中因无法访问 /dev/mem 而无法读取 DMI 数据，
# 但安装后警告消失，hardinfo2 可正常使用其他所有功能。

if ! dpkg -s mesa-utils dmidecode >/dev/null 2>&1; then
    echo "[devtop-init-fix] 安装 hardinfo2 缺失依赖: mesa-utils dmidecode..."
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq mesa-utils dmidecode 2>/dev/null
    echo "[devtop-init-fix] hardinfo2 依赖已安装"
fi

# ========== 修复 4: fcitx5 自启动（保险措施） ==========
# 确保中文输入法自启动配置存在
if [ ! -f "/config/.config/autostart/org.fcitx.Fcitx5.desktop" ]; then
    echo "[devtop-init-fix] fcitx5 自启动缺失，配置中..."
    mkdir -p /config/.config/autostart
    if [ -f "/usr/share/applications/org.fcitx.Fcitx5.desktop" ]; then
        cp /usr/share/applications/org.fcitx.Fcitx5.desktop /config/.config/autostart/
        chown -R 1000:1000 /config/.config/autostart
        echo "[devtop-init-fix] fcitx5 自启动已配置"
    fi
fi

# ========== 修复 5: 复制 Codex 配置到 /config/.codex ==========
# /config 是宿主挂载卷，容器首次启动（或用户误删）时可能缺少 .codex 配置。
# 检查 /config/.codex/config.toml 是否存在，缺失则从内置默认配置复制进去
# （目录不存在时由 mkdir -p 一并创建），并设置属主为 1000:1000。

CODEX_DIR="/config/.codex"
CODEX_FILE="${CODEX_DIR}/config.toml"
CODEX_SRC="/defaults/devtop-config/config.toml"

if [ ! -f "$CODEX_FILE" ]; then
    echo "[devtop-init-fix] 未检测到 Codex 配置，准备复制默认配置..."
    mkdir -p "$CODEX_DIR"
    if [ -f "$CODEX_SRC" ]; then
        cp "$CODEX_SRC" "$CODEX_FILE"
        chown -R 1000:1000 "$CODEX_DIR"
        echo "[devtop-init-fix] Codex 配置已写入 ${CODEX_FILE}"
    else
        echo "[devtop-init-fix] 警告: 默认配置源 ${CODEX_SRC} 不存在，跳过"
    fi
else
    echo "[devtop-init-fix] Codex 配置已存在，跳过复制"
fi

echo "[devtop-init-fix] 修复完成。"
