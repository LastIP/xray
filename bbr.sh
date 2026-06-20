#!/bin/bash

# 檢查 root 權限
[[ $EUID -ne 0 ]] && echo "請以 root 權限運行" && exit 1

echo "檢測到內核版本: $(uname -r)"

# 定義配置文件路徑
# 優先使用 sysctl.d 目錄，如果不存在則使用 sysctl.conf
if [ -d "/etc/sysctl.d" ]; then
    CONF_FILE="/etc/sysctl.d/99-bbr.conf"
else
    CONF_FILE="/etc/sysctl.conf"
fi

echo "正在將配置寫入: $CONF_FILE"

# 移除舊配置（如果文件存在）
if [ -f "$CONF_FILE" ]; then
    sed -i '/net.core.default_qdisc/d' "$CONF_FILE"
    sed -i '/net.ipv4.tcp_congestion_control/d' "$CONF_FILE"
fi

# 寫入新配置
# 使用 tee 以確保即便文件不存在也能創建
echo "net.core.default_qdisc = fq" | tee -a "$CONF_FILE" > /dev/null
echo "net.ipv4.tcp_congestion_control = bbr" | tee -a "$CONF_FILE" > /dev/null

# 生效配置
# 使用 --system 加載所有配置文件，兼容性最強
sysctl --system > /dev/null 2>&1 || sysctl -p "$CONF_FILE" > /dev/null 2>&1

# 驗證
echo "----------------------------------------"
status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$status" == "bbr" ]; then
    echo "✅ BBR 成功開啟！"
else
    # 嘗試手動加載模塊（某些精簡系統需要）
    modprobe tcp_bbr
    status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [ "$status" == "bbr" ]; then
        echo "✅ BBR 成功開啟（透過 modprobe）！"
    else
        echo "❌ BBR 開啟失敗，請檢查內核是否支持。"
    fi
fi
echo "----------------------------------------"