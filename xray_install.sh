#!/bin/bash

# 脚本遇到错误时立即退出
set -e

# --- 用户可配置参数 ---
# Xray 安装目录
PROXY_DIR="$HOME/xray_auto_server"
# Systemd 服务名称 (Xray 用户服务)
XRAY_SERVICE_NAME="xray-user-proxy"
# Xray 本地监听地址 (供 cloudflared 连接)
XRAY_LISTEN_ADDRESS="127.0.0.1"
# Xray 本地监听端口 (供 cloudflared 连接, 根据图示)
XRAY_LISTEN_PORT=32156

# Cloudflare Tunnel 相关配置
# !!! 警告：这是一个非常敏感的 Token，请勿公开分享包含真实 Token 的脚本 !!!
# !!! 如果您要分发此脚本，请将下面的 Token 替换为占位符，例如 "YOUR_CLOUDFLARE_TUNNEL_TOKEN" !!!
CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoiZmEzN2I2NjYzYWM4OWQyNzYwNTYxN2U3MmYxZGFhYzYiLCJ0IjoiYTEyNWExY2EtNWM1YS00NWE2LWI3YmQtOGE2Y2VlYzhkMjMxIiwicyI6Ik9EbGpPVEEwTkdZdFpUVTFZaTAwWlRZekxXSmtPVFF0TlRBMVlUUXhaREZtT0dOaSJ9"
# 您在 Cloudflare Tunnel 中设置的公共主机名 (客户端将连接到此地址)
CLOUDFLARE_PUBLIC_HOSTNAME="idx.frankdevcn.dpdns.org"

# Xray REALITY 伪装的目标域名和端口
REALITY_DEST_DOMAIN="www.microsoft.com"
REALITY_DEST_PORT="443"
# Xray REALITY 使用的 SNI (通常与伪装域名一致或为其子域名, 多个用逗号隔开)
REALITY_SERVER_NAMES="${REALITY_DEST_DOMAIN}" # 用于VLESS链接时，默认取此值的第一个（如果为列表）
# Xray REALITY 客户端指纹
REALITY_FINGERPRINT="chrome"
# Xray 流控设置
FLOW_CONTROL="xtls-rprx-vision"

# --- Xray 版本控制 ---
# !!! 重要 !!!
# 您提供的截图显示 v25.5.16 是您环境中的 "Latest"。脚本将使用您在此处设置的版本。
# 如果 v25.5.16 版本作为服务持续失败，请考虑访问 https://github.com/XTLS/Xray-core/releases
# 查找一个官方的、历史悠久的稳定版本号 (例如 v1.8.x 系列的某个版本) 并在此处更新。
FIXED_XRAY_VERSION="v25.5.16"

# --- 辅助函数 ---
command_exists() { command -v "$1" >/dev/null 2>&1; }
install_base_dependencies() {
    REQUIRED_SOFTWARE=("cURL:curl:curl:curl:curl:curl" "Unzip:unzip:unzip:unzip:unzip:unzip")
    local cmds_to_check_again=(); echo "🔎 正在检查基础依赖项 (curl, unzip)..."; local all_deps_present=true
    for item in "${REQUIRED_SOFTWARE[@]}"; do IFS=":" read -r cn cmd _ <<< "$item"; if ! command_exists "$cmd"; then echo "    - 软件 '$cn' (命令 '$cmd') 未找到."; all_deps_present=false; cmds_to_check_again+=("$cmd"); else echo "    + 命令 '$cmd' 已存在."; fi; done
    if [ "$all_deps_present" = true ]; then echo "👍 所有基础依赖项均已安装。"; return 0; fi
    echo "⚠️  检测到有基础依赖项缺失，将尝试自动安装."; local PM=""; local INSTALL_CMD=""; local UPDATE_CMD=""; local SUDO="sudo"
    if command_exists "apt-get"; then PM="apt"; UPDATE_CMD="apt-get update -qq"; INSTALL_CMD="apt-get install -y";
    elif command_exists "dnf"; then PM="dnf"; UPDATE_CMD="dnf check-update > /dev/null || true"; INSTALL_CMD="dnf install -y";
    elif command_exists "yum"; then PM="yum"; UPDATE_CMD="yum check-update > /dev/null || true"; INSTALL_CMD="yum install -y";
    elif command_exists "pacman"; then PM="pacman"; UPDATE_CMD="pacman -Sy --noconfirm"; INSTALL_CMD="pacman -S --noconfirm --needed";
    elif command_exists "zypper"; then PM="zypper"; UPDATE_CMD="zypper refresh"; INSTALL_CMD="zypper install -y --no-confirm";
    else echo "❌ 无法识别包管理器。请手动安装。"; exit 1; fi; echo "ℹ️  检测到包管理器: $PM"
    if [[ "$(id -u)" == "0" ]]; then SUDO=""; echo "    以root用户身份运行。"; elif ! command_exists "sudo"; then echo "❌ 'sudo' 未找到。"; exit 1; else echo "    将使用 '$SUDO' 执行特权命令。"; fi
    if [ -n "$UPDATE_CMD" ]; then echo "🔄 更新包列表..."; eval "$SUDO $UPDATE_CMD" || { echo "❌ 包列表更新失败。"; exit 1; }; echo "    包列表更新完成。"; fi
    for item in "${REQUIRED_SOFTWARE[@]}"; do IFS=":" read -r cn cmd d_pkg r_pkg a_pkg s_pkg <<< "$item"
        if ! command_exists "$cmd"; then local pkg_to_install=""; case "$PM" in apt) pkg_to_install="$d_pkg";; dnf|yum) pkg_to_install="$r_pkg";; pacman) pkg_to_install="$a_pkg";; zypper) pkg_to_install="$s_pkg";; esac
            if [ -z "$pkg_to_install" ]; then echo "⚠️  包 '$cn' 未定义 for $PM."; continue; fi
            echo "📦 安装 '$pkg_to_install'..."; eval "$SUDO $INSTALL_CMD $pkg_to_install" || { echo "❌ 安装 '$pkg_to_install' 失败."; exit 1; }
    fi; done; echo "🔎 最终验证..."; for cmd_verify in "${cmds_to_check_again[@]}"; do if ! command_exists "$cmd_verify"; then echo "❌ 命令 '$cmd_verify' 仍未找到!"; exit 1; fi; done; echo "✅ 依赖项处理完毕。"; echo "--------------------------------------------------------------------";
}
install_cloudflared_debian() {
    if command_exists "cloudflared"; then echo "👍 cloudflared 已安装 ($(cloudflared --version))."; return 0; fi
    echo "📦 正在尝试为 Debian/Ubuntu 系统安装 cloudflared (需要 sudo 权限)..."; if ! command_exists "sudo"; then echo "❌ 'sudo' 未找到。"; return 1; fi
    echo "    添加 Cloudflare GPG 密钥..."; sudo mkdir -p --mode=0755 /usr/share/keyrings; curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "    添加 Cloudflare APT 仓库..."; echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
    echo "    更新 APT 包列表并安装 cloudflared..."; sudo apt-get update -qq && sudo apt-get install -y cloudflared || { echo "❌ 安装 cloudflared 失败。"; return 1; }; echo "✅ cloudflared 安装成功。";
}

# --- 脚本主流程开始 ---
echo "🚀 开始非root用户 Xray 代理服务器及 Cloudflare Tunnel 部署..."
echo "--------------------------------------------------------------------"
install_base_dependencies
echo "--------------------------------------------------------------------"
if ! install_cloudflared_debian; then echo "⚠️  cloudflared 安装失败或被跳过。Cloudflare Tunnel 将无法工作。"; fi
echo "--------------------------------------------------------------------"
echo "🔧 1. 创建 Xray 安装目录: ${PROXY_DIR}"; mkdir -p "${PROXY_DIR}/bin" "${PROXY_DIR}/etc" "$HOME/.config/systemd/user/"
echo "📥 2. 下载并安装 Xray-core..."; XRAY_TAG_TO_DOWNLOAD="$FIXED_XRAY_VERSION"; echo "    将使用指定版本: ${XRAY_TAG_TO_DOWNLOAD}"
if [[ ! "$XRAY_TAG_TO_DOWNLOAD" == v* ]] && [[ ! "$XRAY_TAG_TO_DOWNLOAD" == "latest" ]]; then XRAY_TAG_TO_DOWNLOAD="v${XRAY_TAG_TO_DOWNLOAD}"; fi
XRAY_ZIP_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_TAG_TO_DOWNLOAD}/Xray-linux-64.zip"
echo "    正在从 ${XRAY_ZIP_URL} 下载..."; curl -L -f -o "${PROXY_DIR}/xray.zip" "${XRAY_ZIP_URL}" || { echo "❌ 下载 Xray ${XRAY_TAG_TO_DOWNLOAD} 失败。请检查版本号或网络。"; exit 1; }
echo "    解压 Xray..."; unzip -o "${PROXY_DIR}/xray.zip" -d "${PROXY_DIR}/bin/" geosite.dat geoip.dat xray || { echo "❌ 解压 Xray 失败。"; exit 1; }
rm "${PROXY_DIR}/xray.zip"; chmod +x "${PROXY_DIR}/bin/xray"; echo "    Xray-core (${XRAY_TAG_TO_DOWNLOAD}) 安装完毕。"
echo "🔑 3. 生成 Xray 配置参数..."; XRAY_EXECUTABLE="${PROXY_DIR}/bin/xray"; USER_UUID=$($XRAY_EXECUTABLE uuid)
KEY_PAIR_OUTPUT=$($XRAY_EXECUTABLE x25519); PRIVATE_KEY=$(echo "${KEY_PAIR_OUTPUT}" | grep 'Private key:' | awk '{print $3}'); PUBLIC_KEY=$(echo "${KEY_PAIR_OUTPUT}" | grep 'Public key:' | awk '{print $3}')
SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 4); echo "    用户 UUID: ${USER_UUID}"; echo "    REALITY Public Key: ${PUBLIC_KEY}"; echo "    REALITY Short ID: ${SHORT_ID}";
echo "⚙️  4. 创建 Xray 配置文件 (${PROXY_DIR}/etc/config.json)..."
IFS=',' read -r -a server_names_array <<< "$REALITY_SERVER_NAMES"; formatted_server_names=""; for name in "${server_names_array[@]}"; do name_trimmed=$(echo "$name" | xargs); if [ -n "$name_trimmed" ]; then formatted_server_names+="\"$name_trimmed\","; fi; done; formatted_server_names=${formatted_server_names%,}
cat > "${PROXY_DIR}/etc/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [ { "listen": "${XRAY_LISTEN_ADDRESS}", "port": ${XRAY_LISTEN_PORT}, "protocol": "vless", "settings": { "clients": [ { "id": "${USER_UUID}", "flow": "${FLOW_CONTROL}" } ], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "show": false, "dest": "${REALITY_DEST_DOMAIN}:${REALITY_DEST_PORT}", "xver": 0, "serverNames": [${formatted_server_names}], "privateKey": "${PRIVATE_KEY}", "shortIds": ["${SHORT_ID}"], "fingerprint": "${REALITY_FINGERPRINT}" } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": false } } ],
  "outbounds": [ { "protocol": "freedom", "settings": {} }, { "protocol": "blackhole", "settings": {}, "tag": "blocked" } ]
}
EOF
echo "    Xray 配置文件创建成功 (监听: ${XRAY_LISTEN_ADDRESS}:${XRAY_LISTEN_PORT})。"
echo "🛠️  5. 创建 Xray systemd 用户服务文件 (~/.config/systemd/user/${XRAY_SERVICE_NAME}.service)..."
cat > "$HOME/.config/systemd/user/${XRAY_SERVICE_NAME}.service" <<EOF
[Unit]
Description=Xray Proxy Server (User Service by script - Minimal v2)
After=network.target network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=${PROXY_DIR}/bin/xray run -config ${PROXY_DIR}/etc/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
Environment="XRAY_LOCATION_ASSET=${PROXY_DIR}/bin"
[Install]
WantedBy=default.target
EOF
echo "    Xray 用户服务文件创建成功 (已使用精简配置)。"
echo "🚀 6. 启动 Xray 用户服务并设置用户登录后自启..."
systemctl --user daemon-reload; systemctl --user enable --now ${XRAY_SERVICE_NAME}.service; sleep 3
if systemctl --user is-active --quiet ${XRAY_SERVICE_NAME}.service; then echo "✅ Xray 用户服务已成功启动并运行！"; else echo "❌ Xray 用户服务启动失败！日志: journalctl --user -u ${XRAY_SERVICE_NAME} -e"; ${PROXY_DIR}/bin/xray run -test -config ${PROXY_DIR}/etc/config.json || echo "    Xray配置检查也失败。"; exit 1; fi
echo "--------------------------------------------------------------------"
if command_exists "cloudflared"; then
    echo "🚀 7. 正在设置并启动 Cloudflared 系统服务 (需要 sudo 权限)..."
    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ] || [ "$CLOUDFLARE_TUNNEL_TOKEN" == "YOUR_CLOUDFLARE_TUNNEL_TOKEN" ]; then echo "⚠️  错误: CLOUDFLARE_TUNNEL_TOKEN 未正确设置。无法安装 Cloudflared 服务。"; else
        echo "    使用 Tunnel Token 安装 cloudflared 服务..."; sudo cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN" || { echo "❌ sudo cloudflared service install 命令失败。"; }
        if systemctl is-active --quiet cloudflared; then echo "✅ cloudflared 系统服务已启动并运行。"; else echo "⚠️  cloudflared 系统服务未能自动启动或状态未知。请手动检查。"; fi
    fi
else echo "⚠️  cloudflared 命令未找到，跳过 Cloudflared 系统服务设置。"; fi
echo "--------------------------------------------------------------------"

echo "🎉🎉🎉 Xray 及 Cloudflare Tunnel 部署流程执行完毕! 🎉🎉🎉"
echo ""
echo "客户端将通过 Cloudflare Tunnel 连接，请使用以下信息配置客户端:"
echo "===================================================================="
echo "服务器地址 (Address/Host): ${CLOUDFLARE_PUBLIC_HOSTNAME}"
echo "服务器端口 (Port):         443 (通常是 HTTPS 默认端口)"
echo "用户ID (UUID):             ${USER_UUID}"
echo "协议 (Protocol):         vless"
echo "传输方式 (Network):      tcp"
echo "TLS (底层安全):         开启 (由 Cloudflare Tunnel 提供)"
echo ""
echo "--- VLESS + REALITY 特定配置 (内层，用于 Xray 客户端) ---"
# 提取 REALITY_SERVER_NAMES 中的第一个作为 VLESS 链接的 SNI
FIRST_SNI_FOR_LINK=$(echo "$REALITY_SERVER_NAMES" | cut -d',' -f1 | xargs)
echo "目标域名 (SNI/伪装域名):   ${FIRST_SNI_FOR_LINK}"
echo "REALITY 公钥 (PublicKey):  ${PUBLIC_KEY}"
echo "REALITY ShortID:         ${SHORT_ID}"
echo "REALITY 指纹 (Fingerprint):${REALITY_FINGERPRINT}"
echo "流控 (Flow):               ${FLOW_CONTROL}"
echo "===================================================================="

# 生成 VLESS 导入链接
CON_ALIAS_RAW="Xray-CF-${CLOUDFLARE_PUBLIC_HOSTNAME}"
# 基本的 URL 编码替换：空格 -> %20, # -> %23, ? -> %3F, & -> %26, = -> %3D
# 对于更复杂的别名，可能需要更完善的URL编码函数
CON_ALIAS_ENCODED=$(echo "$CON_ALIAS_RAW" | sed 's/ /%20/g; s/#/%23/g; s/?/%3F/g; s/&/%26/g; s/=/%3D/g')

VLESS_LINK="vless://${USER_UUID}@${CLOUDFLARE_PUBLIC_HOSTNAME}:443?type=tcp&security=reality&sni=${FIRST_SNI_FOR_LINK}&fp=${REALITY_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=${FLOW_CONTROL}&encryption=none#${CON_ALIAS_ENCODED}"

echo ""
echo "客户端直接导入链接 (VLESS URI):"
echo "===================================================================="
echo "${VLESS_LINK}"
echo "===================================================================="
echo "提示: 您可以将上面的链接复制到兼容的客户端 (如 NekoBox, V2RayN) 中直接导入配置。"
echo ""
echo "重要提示:"
echo "  - 客户端连接的是 Cloudflare 的边缘网络 (${CLOUDFLARE_PUBLIC_HOSTNAME})。"
echo "  - Xray 现在监听在 ${XRAY_LISTEN_ADDRESS}:${XRAY_LISTEN_PORT}，仅供本地 cloudflared 访问。"
echo "  - 请确保 Tunnel (${CLOUDFLARE_PUBLIC_HOSTNAME}) 指向本地服务 http://${XRAY_LISTEN_ADDRESS}:${XRAY_LISTEN_PORT}。"
echo "  - Xray 用户服务日志: journalctl --user -u ${XRAY_SERVICE_NAME} -f"
echo "  - Cloudflared 系统服务日志: sudo journalctl -u cloudflared -f"
echo "  - 若需 Xray 开机自启 (用户登出后运行): sudo loginctl enable-linger $(whoami)"
echo "--------------------------------------------------------------------"

exit 0
