#!/bin/bash

# 脚本遇到错误时立即退出
set -e

# --- 用户可配置参数 ---
# Xray 安装目录
PROXY_DIR="$HOME/xray_auto_server"
# Systemd 服务名称
SERVICE_NAME="xray-user-proxy"
# Xray 监听端口 (确保此端口未被占用且防火墙允许)
LISTENING_PORT=12345
# REALITY 伪装的目标域名和端口 (选择一个常见的大网站)
REALITY_DEST_DOMAIN="www.microsoft.com"
REALITY_DEST_PORT="443"
# REALITY 使用的 SNI (通常与伪装域名一致或为其子域名, 多个用逗号隔开)
REALITY_SERVER_NAMES="${REALITY_DEST_DOMAIN}"
# REALITY 客户端指纹 (例如: "chrome", "firefox", "safari", "ios", "android")
REALITY_FINGERPRINT="chrome"
# 流控设置 (例如: "xtls-rprx-vision", "xtls-rprx-vision-udp443")
FLOW_CONTROL="xtls-rprx-vision"

# --- Xray 版本控制 ---
# 为了稳定性，我们固定一个已知的Xray版本。
# !!! 重要 !!!
# 您提供的截图显示 v25.5.16 是您环境中的 "Latest"。脚本将使用您在此处设置的版本。
# 如果 v25.5.16 版本作为服务持续失败，请考虑访问 https://github.com/XTLS/Xray-core/releases
# 查找一个官方的、历史悠久的稳定版本号 (例如 v1.8.x 系列的某个版本) 并在此处更新。
FIXED_XRAY_VERSION="v25.5.16" # <--- 根据您的截图，这是 "Latest"。如果问题持续，请尝试官方历史稳定版。

# --- 辅助函数 ---

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install missing dependencies across different Linux distributions
install_missing_dependencies() {
    REQUIRED_SOFTWARE=(
        "cURL:curl:curl:curl:curl:curl"
        "Unzip:unzip:unzip:unzip:unzip:unzip"
    )
    local commands_to_check_again=()
    echo "🔎 正在检查依赖项..."
    local all_deps_present=true
    for item in "${REQUIRED_SOFTWARE[@]}"; do
        IFS=":" read -r common_name cmd_name _ <<< "$item"
        if ! command_exists "$cmd_name"; then
            echo "    - 软件 '${common_name}' (命令 '${cmd_name}') 未找到."
            all_deps_present=false
            commands_to_check_again+=("$cmd_name")
        else
            echo "    + 命令 '${cmd_name}' 已存在."
        fi
    done

    if [ "$all_deps_present" = true ]; then
        echo "👍 所有必需的依赖项均已安装。"
        echo "--------------------------------------------------------------------"
        return 0
    fi
    echo "⚠️  检测到有依赖项缺失，将尝试自动安装。"
    local PKG_MANAGER=""
    local INSTALL_CMD_TPL=""
    local UPDATE_CMD_TPL=""
    local SUDO_PREFIX="sudo"

    if command_exists "apt-get"; then PKG_MANAGER="apt"; UPDATE_CMD_TPL="apt-get update -qq"; INSTALL_CMD_TPL="apt-get install -y";
    elif command_exists "dnf"; then PKG_MANAGER="dnf"; UPDATE_CMD_TPL="dnf check-update > /dev/null || true"; INSTALL_CMD_TPL="dnf install -y";
    elif command_exists "yum"; then PKG_MANAGER="yum"; UPDATE_CMD_TPL="yum check-update > /dev/null || true"; INSTALL_CMD_TPL="yum install -y";
    elif command_exists "pacman"; then PKG_MANAGER="pacman"; UPDATE_CMD_TPL="pacman -Sy --noconfirm"; INSTALL_CMD_TPL="pacman -S --noconfirm --needed";
    elif command_exists "zypper"; then PKG_MANAGER="zypper"; UPDATE_CMD_TPL="zypper refresh"; INSTALL_CMD_TPL="zypper install -y --no-confirm";
    else
        echo "❌ 无法识别的包管理器。请手动安装以下软件对应的包，然后重新运行脚本:"
        for cmd_to_check in "${commands_to_check_again[@]}"; do
             for item_spec in "${REQUIRED_SOFTWARE[@]}"; do IFS=":" read -r c_name c_cmd _ <<< "$item_spec"; if [ "$c_cmd" == "$cmd_to_check" ]; then echo "    - ${c_name} (需要命令 '${c_cmd}')"; break; fi; done
        done; exit 1;
    fi
    echo "ℹ️  检测到包管理器: ${PKG_MANAGER}"
    if [[ "$(id -u)" == "0" ]]; then SUDO_PREFIX=""; echo "    以root用户身份运行，将直接执行包管理命令。";
    elif ! command_exists "sudo"; then echo "❌ 'sudo' 命令未找到，并且当前用户不是root。请安装 sudo 或以root用户身份运行此脚本的依赖安装部分，或手动安装缺失的依赖项。"; exit 1;
    else echo "    将使用 '${SUDO_PREFIX}' 执行特权命令 (可能需要您输入密码)。"; fi
    if [ -n "$UPDATE_CMD_TPL" ]; then echo "🔄 正在使用 '${PKG_MANAGER}' 更新包列表 (${SUDO_PREFIX} ${UPDATE_CMD_TPL})..."; eval "${SUDO_PREFIX} ${UPDATE_CMD_TPL}" || { echo "❌ 包列表更新失败。"; exit 1; }; echo "    包列表更新完成。"; fi
    for item in "${REQUIRED_SOFTWARE[@]}"; do
        IFS=":" read -r common_name cmd_name deb_pkg rhel_pkg arch_pkg suse_pkg <<< "$item"
        if ! command_exists "$cmd_name"; then
            local pkg_to_install=""; case "$PKG_MANAGER" in apt) pkg_to_install="$deb_pkg" ;; dnf|yum) pkg_to_install="$rhel_pkg" ;; pacman) pkg_to_install="$arch_pkg" ;; zypper) pkg_to_install="$suse_pkg" ;; esac
            if [ -z "$pkg_to_install" ]; then echo "⚠️  没有为包管理器 '${PKG_MANAGER}' 定义 '${common_name}' 的包名。"; continue; fi
            echo "📦 正在使用 '${PKG_MANAGER}' 安装 '${pkg_to_install}' (提供命令 '${cmd_name}')..."; eval "${SUDO_PREFIX} ${INSTALL_CMD_TPL} ${pkg_to_install}" || { echo "❌ 安装 '${pkg_to_install}' 失败。"; exit 1; }
        fi
    done
    echo "🔎 正在最终验证依赖项安装情况..."
    for cmd_to_verify in "${commands_to_check_again[@]}"; do
        if ! command_exists "$cmd_to_verify"; then
             for item_spec_verify in "${REQUIRED_SOFTWARE[@]}"; do IFS=":" read -r c_name_v c_cmd_v _ <<< "$item_spec_verify"; if [ "$c_cmd_v" == "$cmd_to_verify" ]; then echo "❌ 致命错误: 命令 '${cmd_to_verify}' (来自软件 '${c_name_v}') 仍然未找到。"; exit 1; fi; done
        fi
    done; echo "✅ 所有依赖项已成功安装/验证。"; echo "--------------------------------------------------------------------";
}

# --- 脚本主流程开始 ---

# 0. 安装缺失的依赖项
install_missing_dependencies

echo "🚀 开始非root用户一键部署 Xray 代理服务器 (VLESS + REALITY)..."
echo "--------------------------------------------------------------------"

# 1. 创建目录
echo "🔧 1. 创建安装目录: ${PROXY_DIR}"
mkdir -p "${PROXY_DIR}/bin"
mkdir -p "${PROXY_DIR}/etc"
mkdir -p "$HOME/.config/systemd/user/" # systemd 用户服务目录

# 2. 下载并安装 Xray-core
echo "📥 2. 下载并安装 Xray-core..."
LATEST_TAG="$FIXED_XRAY_VERSION" # 使用固定的版本号
echo "    将使用固定版本: ${LATEST_TAG}"
# 确保版本号前有 "v"
if [[ ! "$LATEST_TAG" == v* ]] && [[ ! "$LATEST_TAG" == "latest" ]]; then # "latest" 本身不需要加 "v"
    LATEST_TAG="v${LATEST_TAG}"
fi
XRAY_ZIP_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_TAG}/Xray-linux-64.zip"

echo "    正在从 ${XRAY_ZIP_URL} 下载..."
curl -L -f -o "${PROXY_DIR}/xray.zip" "${XRAY_ZIP_URL}" || {
    echo "❌ 下载 Xray ${LATEST_TAG} 失败。"
    echo "   请检查以下几点："
    echo "   1. 版本号 '${LATEST_TAG}' 是否真实存在于 https://github.com/XTLS/Xray-core/releases"
    echo "   2. 您的网络连接是否正常。"
    echo "   3. 如果版本号无误，可能是 GitHub Releases 临时出现问题。"
    exit 1;
}
echo "    解压 Xray..."
unzip -o "${PROXY_DIR}/xray.zip" -d "${PROXY_DIR}/bin/" geosite.dat geoip.dat xray || { echo "❌ 解压 Xray 失败 (下载的文件可能不是有效的zip包)。"; exit 1; }
rm "${PROXY_DIR}/xray.zip"
chmod +x "${PROXY_DIR}/bin/xray"
echo "    Xray-core (${LATEST_TAG}) 安装完毕。"

# 3. 生成 Xray 配置参数
echo "🔑 3. 生成 Xray 配置参数..."
XRAY_EXECUTABLE="${PROXY_DIR}/bin/xray"

USER_UUID=$($XRAY_EXECUTABLE uuid)
echo "    用户 UUID: ${USER_UUID}"

KEY_PAIR_OUTPUT=$($XRAY_EXECUTABLE x25519)
PRIVATE_KEY=$(echo "${KEY_PAIR_OUTPUT}" | grep 'Private key:' | awk '{print $3}')
PUBLIC_KEY=$(echo "${KEY_PAIR_OUTPUT}" | grep 'Public key:' | awk '{print $3}')
echo "    REALITY Private Key: ${PRIVATE_KEY}"
echo "    REALITY Public Key: ${PUBLIC_KEY}"

SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)
echo "    REALITY Short ID: ${SHORT_ID}"

# 4. 创建 Xray 配置文件
echo "⚙️  4. 创建 Xray 配置文件 (${PROXY_DIR}/etc/config.json)..."
IFS=',' read -r -a server_names_array <<< "$REALITY_SERVER_NAMES"
formatted_server_names=""
for name in "${server_names_array[@]}"; do
    name_trimmed=$(echo "$name" | xargs)
    if [ -n "$name_trimmed" ]; then formatted_server_names+="\"$name_trimmed\","; fi
done
formatted_server_names=${formatted_server_names%,}

cat > "${PROXY_DIR}/etc/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${LISTENING_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}",
            "flow": "${FLOW_CONTROL}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST_DOMAIN}:${REALITY_DEST_PORT}",
          "xver": 0,
          "serverNames": [${formatted_server_names}],
          "privateKey": "${PRIVATE_KEY}",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": ["${SHORT_ID}"],
          "fingerprint": "${REALITY_FINGERPRINT}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOF
echo "    配置文件创建成功。"

# 5. 创建 systemd 用户服务文件 (尝试更精简的配置)
echo "🛠️  5. 创建 systemd 用户服务文件 (~/.config/systemd/user/${SERVICE_NAME}.service)..."
cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Xray Proxy Server (User Service by script - Minimal v2)
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
# User=%U
# SupplementaryGroups=
# 上述 User 和 SupplementaryGroups 指令已在此版本中移除，以测试是否能避免环境限制。
# 服务将默认以运行 systemd --user 实例的用户身份执行。
ExecStart=${PROXY_DIR}/bin/xray run -config ${PROXY_DIR}/etc/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
Environment="XRAY_LOCATION_ASSET=${PROXY_DIR}/bin"

[Install]
WantedBy=default.target
EOF
echo "    服务文件创建成功 (已使用更精简的配置)。"

# 6. 启动并设置开机自启 (用户层面)
echo "🚀 6. 启动服务并设置用户登录后自启..."
systemctl --user daemon-reload
systemctl --user enable --now ${SERVICE_NAME}.service

# 检查服务状态
echo "    正在检查服务状态..."
sleep 3 # 等待服务启动
if systemctl --user is-active --quiet ${SERVICE_NAME}.service; then
  echo "✅ 服务已成功启动并运行！"
else
  echo "❌ 服务启动失败！请检查日志: journalctl --user -u ${SERVICE_NAME} -e"
  echo "    尝试运行Xray配置检查:"
  ${PROXY_DIR}/bin/xray run -test -config ${PROXY_DIR}/etc/config.json || echo "    Xray配置检查也失败了。"
  exit 1
fi
echo "--------------------------------------------------------------------"

# 7. 输出客户端连接信息
SERVER_IP_GUESS=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$SERVER_IP_GUESS" ]; then SERVER_IP_GUESS="<你的服务器IP地址>"; fi

echo "🎉🎉🎉 Xray 代理服务器部署完成! 🎉🎉🎉"
echo ""
echo "以下是您的客户端连接信息:"
echo "===================================================================="
echo "服务器地址 (Address):     ${SERVER_IP_GUESS} (如果是云服务器或NAT后, 请使用公网IP)"
echo "服务器端口 (Port):         ${LISTENING_PORT}"
echo "用户ID (UUID):             ${USER_UUID}"
echo "协议 (Protocol):         vless"
echo "传输方式 (Network):      tcp"
echo "安全类型 (Security):     reality"
echo "流控 (Flow):               ${FLOW_CONTROL}"
echo ""
echo "--- REALITY 配置 ---"
echo "SNI (ServerNames/Host):    ${REALITY_SERVER_NAMES}"
echo "公钥 (PublicKey):          ${PUBLIC_KEY}"
echo "ShortID:                 ${SHORT_ID}"
echo "指纹 (Fingerprint):        ${REALITY_FINGERPRINT}"
echo "===================================================================="
echo ""
echo "提示:"
echo "  - 如果服务器IP显示的是内网IP (如 192.168.x.x 或 10.x.x.x), 或为空, 且您希望从公网访问,"
echo "    请手动将其替换为您的服务器公网IP地址。"
echo "  - 确保端口 ${LISTENING_PORT} 在服务器防火墙 (如ufw) 和云服务商安全组中已开放 (TCP&UDP)。"
echo "  - 要使服务在您退出登录后依旧运行, 请为您的用户启用 lingering:"
echo "    sudo loginctl enable-linger $(whoami) (此命令通常需要sudo权限, 但只需执行一次)"
echo "  - 查看服务日志: journalctl --user -u ${SERVICE_NAME} -f"
echo "  - 停止服务: systemctl --user stop ${SERVICE_NAME}"
echo "  - 卸载服务和文件 (可使用配套的卸载脚本，或手动执行):"
echo "    systemctl --user disable --now ${SERVICE_NAME} && rm -rf ${PROXY_DIR} ~/.config/systemd/user/${SERVICE_NAME}.service && systemctl --user daemon-reload"
echo "--------------------------------------------------------------------"

exit 0
