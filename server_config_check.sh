#!/bin/bash

# 额外指定频繁输出颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function check_config_file() {
    echo -e "${YELLOW}====== 检查 cloudflared 配置文件 /etc/cloudflared/config.yml ======${NC}"
    if grep -q 'service: http://127.0.0.1:2080' /etc/cloudflared/config.yml; then
        echo -e "${GREEN}cloudflared 配置正确 (指向 127.0.0.1:2080)。${NC}"
    else
        echo -e "${RED}ERROR: cloudflared 配置错误，应该指向 127.0.0.1:2080。${NC}"
        exit 1
    fi
}

function check_singbox_port() {
    echo -e "${YELLOW}====== 检查 sing-box 是否监听 127.0.0.1:2080 ======${NC}"
    if ss -tunlp | grep -q ':2080'; then
        echo -e "${GREEN}sing-box 正在监听 2080 端口。${NC}"
    else
        echo -e "${RED}ERROR: sing-box 未监听 2080 端口。${NC}"
        exit 1
    fi
}

function check_cloudflared_running() {
    echo -e "${YELLOW}====== 检查 cloudflared 服务状态 ======${NC}"
    if systemctl is-active --quiet cloudflared; then
        echo -e "${GREEN}cloudflared 正常运行。${NC}"
    else
        echo -e "${RED}ERROR: cloudflared 没有运行。${NC}"
        exit 1
    fi
}

function test_curl_request() {
    echo -e "${YELLOW}====== 测试 curl 请求 cloudflare tunnel ======${NC}"
    curl -s -o /dev/null -w "%{http_code}" --http1.1 https://socks.frankwong.dpdns.org/ -k | grep -q '^4\|^5'
    if [ $? -eq 0 ]; then
        echo -e "${RED}ERROR: curl 返回 4xx/5xx，有故障。${NC}"
    else
        echo -e "${GREEN}curl 请求成功！。${NC}"
    fi
}

# 次序执行
check_config_file
check_singbox_port
check_cloudflared_running
test_curl_request

echo -e "\n${GREEN}==== 检查完成！没有错误 ====${NC}"
