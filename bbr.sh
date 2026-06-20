#!/bin/bash

# 檢查 root 權限
[[ $EUID -ne 0 ]] && echo "請以 root 權限運行" && exit 1

echo "----------------------------------------"
echo "正在開始 BBR 優化腳本..."
echo "系統內核: $(uname -r)"

# 1. 定義配置文件路徑
if [ -d "/etc/sysctl.d" ]; then
    CONF_FILE="/etc/sysctl.d/99-network-opt.conf"
else
    CONF_FILE="/etc/sysctl.conf"
fi

# 2. 清理舊的相關配置（避免重複）
if [ -f "$CONF_FILE" ]; then
    sed -i '/net.core.default_qdisc/d' "$CONF_FILE"
    sed -i '/net.ipv4.tcp_congestion_control/d' "$CONF_FILE"
    sed -i '/net.ipv4.tcp_fastopen/d' "$CONF_FILE"
    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$CONF_FILE"
    sed -i '/net.ipv4.tcp_rmem/d' "$CONF_FILE"
    sed -i '/net.ipv4.tcp_wmem/d' "$CONF_FILE"
fi

# 3. 寫入 BBR 及 網絡優化參數
echo "正在寫入優化配置到: $CONF_FILE"
cat << EOF | tee -a "$CONF_FILE" > /dev/null
# 啟用 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP 窗口與緩衝區優化 (提升高延遲環境下的速度)
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1

# 減少連接斷開後的慢啟動 (有利於網頁瀏覽)
net.ipv4.tcp_slow_start_after_idle = 0

# 啟用 TCP Fast Open (降低握手延遲)
net.ipv4.tcp_fastopen = 3
EOF

# 4. 生效配置
sysctl --system > /dev/null 2>&1 || sysctl -p "$CONF_FILE" > /dev/null 2>&1

# 5. 檢測與驗證
echo "----------------------------------------"
echo "正在檢測開啟狀態："

# 檢查算法
current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')

if [ "$current_cc" == "bbr" ]; then
    echo "✅ TCP 擁塞控制算法: $current_cc (成功)"
else
    # 嘗試加載模塊
    modprobe tcp_bbr >/dev/null 2>&1
    current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [ "$current_cc" == "bbr" ]; then
        echo "✅ TCP 擁塞控制算法: $current_cc (透過 modprobe 成功)"
    else
        echo "❌ TCP 擁塞控制算法開啟失敗: $current_cc"
    fi
fi

if [ "$current_qdisc" == "fq" ]; then
    echo "✅ 隊列調度算法: $current_qdisc (成功)"
else
    echo "⚠️ 隊列調度算法: $current_qdisc (建議設為 fq)"
fi

# 檢查內核模塊
if lsmod | grep -q "bbr"; then
    echo "✅ BBR 內核模塊: 已加載"
else
    # 有些內核（如你提到的 7.0.0）可能直接編譯進內核而非模塊，所以不顯示也可能正常
    if [ "$current_cc" == "bbr" ]; then
        echo "ℹ️  BBR 內核模塊: 已內置於內核"
    else
        echo "❌ BBR 內核模塊: 未發現"
    fi
fi

echo "----------------------------------------"
echo "優化完成！建議重啟相關網絡服務或系統以獲得最佳效果。"