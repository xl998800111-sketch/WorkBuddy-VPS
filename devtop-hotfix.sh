#!/bin/bash
# devtop-hotfix.sh — Devtop Base v1.5 运行时热修复脚本
# 在容器内执行，立即修复 P0 问题
set -e

echo "===== 1. 修复 fcitx5 自启动 ====="
mkdir -p /config/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop /config/.config/autostart/
echo "✅ fcitx5 自启动已配置"

echo "===== 2. 创建中文输入帮助文档 ====="
cat > /workspace/webtop-env.md << 'MDEOF'
# 中文输入法使用说明

## 快捷键
- `Ctrl+Space`: 切换中英文输入
- `Shift`: 临时切换英文（在中文模式下）
- `Ctrl+.`: 切换全角/半角标点

## 输入法
- **拼音输入法**: 默认输入法，支持拆字、符号、英文候选词
- **双拼**: 自然码方案（可在 fcitx5 配置中切换）

## 排查
如输入法未启动，终端执行:
```bash
fcitx5 -d --replace
```

## 配置工具
终端执行 `fcitx5-config-qt` 打开图形配置界面。
MDEOF
echo "✅ 中文输入帮助文档已创建"

echo "===== 3. APT 换阿里云镜像 ====="
sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
sed -i 's|http://security.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
echo "✅ APT 已切换到阿里云镜像"

echo "===== 4. pip 换阿里云镜像 ====="
cat > /etc/pip.conf << 'EOF'
[global]
index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = mirrors.aliyun.com
EOF
echo "✅ pip 已切换到阿里云镜像"

echo "===== 5. npm 换淘宝镜像 ====="
npm config set registry https://registry.npmmirror.com
echo "✅ npm 已切换到淘宝镜像"

echo "===== 6. Go 换七牛镜像 ====="
go env -w GOPROXY=https://goproxy.cn,direct
echo "✅ Go GOPROXY 已切换到七牛镜像"

echo "===== 7. Cargo 换上海交大镜像 ====="
mkdir -p /usr/local/cargo
cat > /usr/local/cargo/config.toml << 'EOF'
[source.crates-io]
replace-with = "sjtu"
[source.sjtu]
registry = "sparse+https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/"
EOF
echo "✅ Cargo 已切换到上海交大镜像"

echo "===== 8. Docker 镜像加速 ====="
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{"registry-mirrors":["https://docker.mirrors.sjtug.sjtu.edu.cn","https://docker.mirrors.ustc.edu.cn"]}
EOF
echo "✅ Docker 镜像加速已配置"

echo ""
echo "========================================"
echo "  热修复完成！请重启容器使所有配置生效"
echo "  执行: docker compose restart webtop"
echo "========================================"
