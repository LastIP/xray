#!/bin/bash

# 檢查是否為 root 用戶
if [[ $EUID -ne 0 ]]; then
   echo "此腳本必須以 root 權限運行。"
   exit 1
fi

# 1. 檢查 Linux 內核版本 (需 4.9 以上)
kernel_version=$(uname -r | cut -d- -f1)
main_version=$(echo $kernel_version | cut -d. -f1)
minor_version=$(echo $kernel_version | cut -d. -f2)

if [ "$main_version" -lt 4 ] || ([ "$main_version" -eq 4 ] && [ "$minor_version" -lt 9 ]); then
    echo "錯誤：當前內核版本為 $kernel_version，BBR 需要 4.9 或更高版本。"
    echo "請先升級您的 Linux 內核。"
    exit 1
fi

echo "檢測到內核版本為 $kernel_version，符合 BBR 開啟條件。"

# 2. 清除舊的配置（避免重複）
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

# 3. 寫入新配置
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf

# 4. 生效配置
sysctl -p > /dev/null

# 5. 驗證是否成功
echo "----------------------------------------"
status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$status" == "bbr" ]; then
    echo "BBR 成功開啟！"
else
    echo "BBR 開啟失敗，請檢查系統日誌。"
    exit 1
fi

lsmod_check=$(lsmod | grep bbr)
if [ -n "$lsmod_check" ]; then
    echo "BBR 模組已載入。"
fi
echo "----------------------------------------"