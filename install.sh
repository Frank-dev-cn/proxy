#!/bin/bash
set -e

# 版本定义
SING_BOX_VERSION="1.8.5"
ARCH=$(uname -m)

# 检测架构
case "$ARCH" in
  x86_64)
    PLATFORM="linux-amd64"
    ;;
  aarch64)
    PLATFORM="linux-arm64"
    ;;
  armv7l)
    PLATFORM="linux-armv7"
    ;;
  *)
    echo "❌ 不支持的架构: $ARCH"
    exit 1
    ;;
esac

# 安装依赖
echo "📦 安装必要组件..."
apt update -y
apt install -y curl wget unzip qrencode

# 安装 sing-box
echo "📥 下载并安装 sing-box..."
curl -LO "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-${PLATFORM}.tar.gz"
tar -zxf sing-box-${SING_BOX_VERSION}-${PLATFORM}.tar.gz
cp sing-box-${SING_BOX_VERSION}-${PLATFORM}/sing-box /usr/bin/sb
chmod +x /usr/bin/sb

# 准备配置目录
mkdir -p /etc/sb
mkdir -p /etc/systemd/system/

# 写入 sing-box config（含远程代理）
echo "🛠️ 写入 sing-box 配置..."
cat <<EOF > /etc/sb/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-google",
        "address": "8.8.8.8"
      },
      {
        "tag": "dns-cloudflare",
        "address": "1.1.1.1"
      }
    ]
  },
  "inbounds": [
    {
      "type": "socks",
      "listen": "0.0.0.0",
      "listen_port": 1080,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

# systemd 管理 sing-box
echo "🛠️ 写入 sb systemd 服务..."
cat <<EOF > /etc/systemd/system/sb.service
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/bin/sb run -c /etc/sb/config.json
Restart=on-failure
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动 sing-box
echo "🔄 启动 sing-box..."
systemctl daemon-reload
systemctl enable sb
systemctl restart sb

# 安装 cloudflared
echo "📥 安装 cloudflared..."
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

# 写守护脚本
echo "🛠️ 写入 cloudflared 自动重连脚本..."
cat <<EOF > /usr/local/bin/cloudflared-run.sh
#!/bin/bash
while true; do
    cloudflared tunnel --url socks5://localhost:1080
    echo "Cloudflared 隧道断了，10秒后重连..."
    sleep 10
done
EOF
chmod +x /usr/local/bin/cloudflared-run.sh

# 写 systemd 管理 cloudflared
echo "🛠️ 写入 cloudflared systemd 服务..."
cat <<EOF > /etc/systemd/system/cloudflared.service
[Unit]
Description=cloudflared tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared-run.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启动 cloudflared
echo "🔄 启动 cloudflared 隧道..."
systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

# 等待 cloudflared 建立隧道
echo "⏳ 等待 10秒建立隧道..."
sleep 10

# 打印隧道地址
TUNNEL_URL=$(cat /var/log/cloudflared.log | grep -m1 -o 'https://[^ ]*')
echo "🌍 你的公网访问地址是：$TUNNEL_URL"

# 生成 socks5 代理二维码
echo "📱 正在生成 Socks5 代理二维码..."
PROXY_URL="${TUNNEL_URL#https://}:443"
qrencode -t ANSIUTF8 "socks5h://$PROXY_URL"

echo "✅ 安装完毕！请用手机扫码或者手动配置代理：$PROXY_URL"
