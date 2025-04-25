#!/bin/bash
set -e

# 版本定义
SING_BOX_VERSION="1.8.5"
ARCH=$(uname -m)

# 检查架构
case "$ARCH" in
  x86_64) PLATFORM="linux-amd64" ;;
  aarch64) PLATFORM="linux-arm64" ;;
  armv7l) PLATFORM="linux-armv7" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 自动安装依赖
for cmd in curl wget qrencode; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "🔧 缺少 $cmd，正在安装..."
        apt install -y $cmd
    fi
done

# 停止已有服务
echo "🛑 检查并停止旧服务..."
systemctl stop sb 2>/dev/null || true
systemctl stop cloudflared 2>/dev/null || true

# 安装 sing-box
echo "📥 下载并安装 sing-box..."
curl -LO "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-${PLATFORM}.tar.gz"
tar -zxf sing-box-${SING_BOX_VERSION}-${PLATFORM}.tar.gz
cp sing-box-${SING_BOX_VERSION}-${PLATFORM}/sing-box /usr/bin/sb
chmod +x /usr/bin/sb

# 配置 sing-box
mkdir -p /etc/sb
cat <<EOF > /etc/sb/config.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "dns-google", "address": "8.8.8.8" },
      { "tag": "dns-cloudflare", "address": "1.1.1.1" }
    ]
  },
  "inbounds": [
    { "type": "socks", "listen": "0.0.0.0", "listen_port": 1080, "sniff": true }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF

# 配置 sb systemd 服务
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
systemctl daemon-reload
systemctl enable sb
systemctl restart sb

# 安装 cloudflared
echo "📥 安装 cloudflared..."
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

# cloudflared 自动守护脚本
cat <<EOF > /usr/local/bin/cloudflared-run.sh
#!/bin/bash
mkdir -p /var/log
while true; do
    cloudflared tunnel --url socks5://localhost:1080 2>&1 | tee /var/log/cloudflared.log
    echo "Cloudflared 隧道断了，10秒后重连..."
    sleep 10
done
EOF
chmod +x /usr/local/bin/cloudflared-run.sh

# cloudflared systemd 服务
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
systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

# 等待建立隧道
sleep 10

# 获取隧道地址
TUNNEL_URL=$(cat /var/log/cloudflared.log | grep -m1 -o 'https://[^ ]*')

# 输出结果
if [[ -z "$TUNNEL_URL" ]]; then
  echo "❗ 没找到隧道地址，cloudflared 可能还没连接成功，请手动检查 /var/log/cloudflared.log"
else
  echo "🌍 你的公网访问地址是：$TUNNEL_URL"
  echo "📱 正在生成 Socks5 代理二维码..."
  PROXY_URL="${TUNNEL_URL#https://}:443"
  qrencode -t ANSIUTF8 "socks5h://$PROXY_URL"
  echo "✅ 安装完成，手机扫码或手动配置 Socks5 地址：$PROXY_URL"
fi
