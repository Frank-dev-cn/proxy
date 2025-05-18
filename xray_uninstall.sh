#!/bin/bash

# 一键卸载脚本：用于移除由一键安装脚本部署的 Xray 代理服务器。
# 此脚本将以非交互方式运行，并尝试恢复安装脚本所做的更改。

# --- 配置 (必须与安装脚本中的默认值匹配) ---
# 安装脚本使用的 Xray 安装目录
PROXY_DIR="$HOME/xray_auto_server"
# 安装脚本使用的 Systemd 服务名称
SERVICE_NAME="xray-user-proxy"

# --- 脚本开始 ---
echo "🚀 开始卸载由一键脚本部署的 Xray 代理服务器..."
echo "--------------------------------------------------------------------"
# 如果任何命令失败，则立即停止执行
set -e

# 1. 停止并禁用 systemd 用户服务
echo "⚙️  1. 停止并禁用 systemd 用户服务 (${SERVICE_NAME})..."
# 检查服务是否正在运行，如果是则停止
if systemctl --user is-active --quiet ${SERVICE_NAME}.service; then
    systemctl --user stop ${SERVICE_NAME}.service
    echo "    服务 (${SERVICE_NAME}) 已停止。"
else
    echo "    服务 (${SERVICE_NAME}) 未在运行或已停止。"
fi

# 检查服务是否已启用 (开机自启)，如果是则禁用
if systemctl --user is-enabled --quiet ${SERVICE_NAME}.service; then
    systemctl --user disable ${SERVICE_NAME}.service
    echo "    服务 (${SERVICE_NAME}) 已禁用 (取消用户登录后自启)。"
else
    echo "    服务 (${SERVICE_NAME}) 未设置为用户登录后自启或已被禁用。"
fi

# 2. 移除 systemd 用户服务文件
SERVICE_FILE_PATH="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
echo "🗑️  2. 移除 systemd 用户服务文件 (${SERVICE_FILE_PATH})..."
if [ -f "${SERVICE_FILE_PATH}" ]; then
    rm -f "${SERVICE_FILE_PATH}"
    echo "    服务文件 (${SERVICE_FILE_PATH}) 已移除。"
else
    echo "    服务文件 (${SERVICE_FILE_PATH}) 未找到。"
fi

# 3. 重新加载 systemd 用户守护进程
echo "🔄  3. 重新加载 systemd 用户守护进程..."
systemctl --user daemon-reload
echo "    systemd 用户守护进程已重新加载。"

# 4. 移除 Xray 安装目录
echo "🗑️  4. 移除 Xray 安装目录 (${PROXY_DIR})..."
if [ -d "${PROXY_DIR}" ]; then
    rm -rf "${PROXY_DIR}"
    echo "    Xray 安装目录 (${PROXY_DIR}) 已移除。"
else
    echo "    Xray 安装目录 (${PROXY_DIR}) 未找到。"
fi

echo "--------------------------------------------------------------------"
echo "✅ Xray 代理服务器卸载完成。"
echo ""
echo "重要提示:"
echo "  - 此脚本已尝试移除 Xray 用户服务及其主要文件和目录。"
echo "  - 通用依赖项 (例如 curl, unzip) 未被卸载，因为它们可能是系统预装的或被其他应用所需要。"
echo "  - 如果您之前为您的用户手动启用了 lingering (例如通过: sudo loginctl enable-linger $(whoami) 或 sudo loginctl enable-linger user)，"
echo "    并且您不再需要任何用户服务在登出后继续运行，您可以考虑手动禁用它。命令如下："
echo "    sudo loginctl disable-linger user"
echo "    (请注意：此命令需要 sudo 权限，并且会影响该用户所有需要 lingering 的服务)。"
echo "  - 如果您曾为 Xray 的端口 (例如 ${LISTENING_PORT:-12345}) 手动添加过防火墙规则，" # 使用变量或默认值提示端口
echo "    您需要手动移除这些防火墙规则。"
echo "--------------------------------------------------------------------"

exit 0
