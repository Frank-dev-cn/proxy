#!/bin/bash
set -e

# === 基础配置 ===
DOMAIN="socks.frankwong.dpdns.org"
TUNNEL_NAME="socks-tunnel"
CONFIG_DIR="/etc/cloudflared"
TUNNEL_DIR="${CONFIG_DIR}/tunnels"

echo "📦 安装依赖..."
apt update -y
apt install -y curl wget unzip qrencode

# ========== 自动停止已有服务 ========== 
echo "🛑 检查 sb 服务状态..."
if systemctl list-units --full --all | grep -Fq 'sb.service'; then
    echo "🛑 sb.service 正在运行，正在停止..."
    systemctl stop sb || true
fi

echo "🛑 检查 cloudflared 服务状态..."
if systemctl list-units --full --all | grep -Fq 'cloudflared.service'; then
    echo "🛑 cloudflared.service 正在运行，正在停止..."
    systemctl stop cloudflared || true
fi

# ========== 安装 cloudflared ========== 
echo "📥 安装 cloudflared..."
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

# ========== 安装 sing-box ========== 
echo "📥 安装 sing-box..."
ARCH=$(uname -m)
SING_BOX_VERSION="1.8.5"
case "$ARCH" in
  x86_64) PLATFORM="linux-amd64" ;;
  aarch64) PLATFORM="linux-arm64" ;;
  armv7l) PLATFORM="linux-armv7" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

curl -LO "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-${PLATFORM}.tar.gz"
tar -zxf sing-box-${SING_BOX_VERSION}-${PLATFORM}.tar.gz
cp sing-box-${SING_BOX_VERSION}-${PLATFORM}/sing-box /usr/bin/sb
chmod +x /usr/bin/sb

# ========== Cloudflare 登录授权 ========== 
echo "🌐 请在弹出的浏览器中登录 Cloudflare 账户以授权此主机..."
cloudflared tunnel login

# ========== 检查并删除已存在的 Tunnel ========== 
echo "🚧 检查 Tunnel 是否已存在..."
if cloudflared tunnel list | grep -Fq "$TUNNEL_NAME"; then
    echo "⚠️ Tunnel '$TUNNEL_NAME' 已存在，正在删除..."
    cloudflared tunnel delete "$TUNNEL_NAME"
fi

# ========== 创建 Tunnel ========== 
echo "🚧 正在创建 Tunnel: $TUNNEL_NAME ..."
cloudflared tunnel create "$TUNNEL_NAME"

# ========== 配置 sing-box ========== 
mkdir -p /etc/sb
cat <<EOF > /etc/sb/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      { "address": "8.8.8.8" },
      { "address": "1.1.1.1" }
    ]
  },
  "inbounds": [
    {
      "type": "socks",
      "listen": "127.0.0.1",
      "listen_port": 1080,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# ========== 写 cloudflared 配置 ========== 
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

mkdir -p "$CONFIG_DIR"
cat <<EOF > $CONFIG_DIR/config.yml
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_DIR/${TUNNEL_ID}.json

ingress:
  - hostname: $DOMAIN
    service: socks5://localhost:1080
  - service: http_status:404
EOF

# ========== 配置 systemd 服务 ========== 
echo "🛠️ 写入 systemd 服务..."

cat <<EOF > /etc/systemd/system/sb.service
[Unit]
Description=sing-box proxy
After=network.target

[Service]
ExecStart=/usr/bin/sb run -c /etc/sb/config.json
Restart=on-failure
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# ========== 启动服务 ========== 
echo "🔄 启动 sb 和 cloudflared..."
systemctl daemon-reload
systemctl enable sb
systemctl enable cloudflared
systemctl restart sb
systemctl restart cloudflared

sleep 5

# ========== 输出 Socks5 地址和二维码 ========== 
echo "✅ 安装完成，公网 Socks5 地址如下："
echo "🌍 socks5h://$DOMAIN:443"

echo "📱 正在生成 Socks5 代理二维码..."
qrencode -t ANSIUTF8 "socks5h://$DOMAIN:443"
