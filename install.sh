#!/bin/bash
set -e

echo "正在更新软件源并安装必要组件..."
apt update -y
apt install -y curl unzip

echo "正在准备目录..."
mkdir -p /etc/sb
mkdir -p /etc/systemd/system/

echo "正在下载 sing-box 最新版本..."
curl -L -o sb.tar.gz https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.tar.gz

echo "正在解压并安装 sing-box..."
tar -zxf sb.tar.gz
cp sing-box*/sing-box /usr/bin/sb
chmod +x /usr/bin/sb

echo "正在下载服务文件和默认配置..."
curl -L -o /etc/systemd/system/sb.service https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.service
curl -L -o /etc/sb/config.json https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/config.json

echo "正在注册并启动服务..."
systemctl daemon-reload
systemctl enable sb
systemctl restart sb

echo "✅ sing-box 安装完成并已启动！"
