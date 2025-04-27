#!/bin/bash

# Advanced Cloudflared + Sing-box Status Checker
# Author: ChatGPT
# Save as: check_status.sh
# Run: bash check_status.sh

LOG_FILE="/root/check_log.txt"
ERR_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "===== 检查开始 =====" | tee "$LOG_FILE"
echo "日志保存到: $LOG_FILE"
echo ""

# 检查 cloudflared 配置文件
CONFIG_FILE="/etc/cloudflared/config.yml"
echo -e "${YELLOW}检查 cloudflared 配置文件...${NC}" | tee -a "$LOG_FILE"
if grep -q 'service: http://127.0.0.1:2080' "$CONFIG_FILE"; then
  echo -e "${GREEN}✅ cloudflared 配置正确 (指向 127.0.0.1:2080)${NC}" | tee -a "$LOG_FILE"
else
  echo -e "${RED}❌ cloudflared 配置错误${NC}" | tee -a "$LOG_FILE"
  ((ERR_COUNT++))
fi

# 检查 sing-box 是否监听 127.0.0.1:2080
echo -e "\n${YELLOW}检查 sing-box 端口监听 (127.0.0.1:2080)...${NC}" | tee -a "$LOG_FILE"
if ss -tunlp | grep -q '127.0.0.1:2080'; then
  echo -e "${GREEN}✅ sing-box 正在监听 2080 端口${NC}" | tee -a "$LOG_FILE"
else
  echo -e "${RED}❌ sing-box 没有监听 2080 端口${NC}" | tee -a "$LOG_FILE"
  ((ERR_COUNT++))
fi

# 检查 cloudflared 服务
echo -e "\n${YELLOW}检查 cloudflared 服务状态...${NC}" | tee -a "$LOG_FILE"
if systemctl is-active --quiet cloudflared; then
  echo -e "${GREEN}✅ cloudflared 正常运行${NC}" | tee -a "$LOG_FILE"
else
  echo -e "${RED}❌ cloudflared 没有运行${NC}" | tee -a "$LOG_FILE"
  ((ERR_COUNT++))
fi

# 测试 curl 请求
echo -e "\n${YELLOW}测试通过 cloudflare tunnel 访问...${NC}" | tee -a "$LOG_FILE"
CURL_OUTPUT=$(curl -s -o /dev/null -w "%{http_code}" --http1.1 -k https://socks.frankwong.dpdns.org/)

if [[ "$CURL_OUTPUT" == "200" ]]; then
  echo -e "${GREEN}✅ curl 请求成功，返回 200${NC}" | tee -a "$LOG_FILE"
elif [[ "$CURL_OUTPUT" == 4* || "$CURL_OUTPUT" == 5* ]]; then
  echo -e "${RED}❌ curl 返回错误状态码: $CURL_OUTPUT${NC}" | tee -a "$LOG_FILE"
  ((ERR_COUNT++))
else
  echo -e "${RED}❌ curl 无响应或其他错误，返回: $CURL_OUTPUT${NC}" | tee -a "$LOG_FILE"
  ((ERR_COUNT++))
fi

# 总结
echo "" | tee -a "$LOG_FILE"
echo "===== 检查完成 =====" | tee -a "$LOG_FILE"
if [ "$ERR_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✅ 没有发现任何错误${NC}" | tee -a "$LOG_FILE"
else
  echo -e "${RED}❌ 检测到 ${ERR_COUNT} 个问题，请检查上面的信息${NC}" | tee -a "$LOG_FILE"
fi

exit 0
