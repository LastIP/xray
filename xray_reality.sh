#!/bin/bash

# ====================================================
# VLESS-REALITY 安全安装脚本 (Docker 保护版)
# 特点：全本地生成，不干扰现有容器，自动检查环境
# ====================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

PORT=8443

echo -e "${BLUE}开始安装 VLESS-Reality 环境...${NC}"

# 1. 检查并安装基础依赖 (非破坏性)
echo -e "${GREEN}[1/6] 检查系统环境...${NC}"

# 检查是否为 Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}错误: 请使用 sudo 或 root 账号运行此脚本${NC}"
  exit 1
fi

# 检查 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    echo -e "${BLUE}检测到未安装 Docker，正在尝试安装...${NC}"
    if grep -Eqi "debian|ubuntu" /etc/issue; then
        apt update && apt install -y uuid-runtime qrencode docker.io curl openssl
    elif grep -Eqi "centos|redhat" /etc/issue; then
        yum install -y util-linux qrencode docker curl openssl
        systemctl start docker && systemctl enable docker
    fi
else
    echo -e "${BLUE}Docker 已存在，跳过安装，保持原有 Docker 环境不变。${NC}"
    # 确保依赖包 uuidgen 和 qrencode 存在
    if ! command -v uuidgen &> /dev/null || ! command -v qrencode &> /dev/null; then
        if grep -Eqi "debian|ubuntu" /etc/issue; then
            apt update && apt install -y uuid-runtime qrencode curl openssl
        elif grep -Eqi "centos|redhat" /etc/issue; then
            yum install -y util-linux qrencode curl openssl
        fi
    fi
fi

# 2. 端口冲突检查
# PORT=8443
if command -v ss &> /dev/null; then
    if ss -tulnp | grep -q ":$PORT "; then
        echo -e "${RED}错误: 端口 $PORT 已被占用，请先停止相关服务或修改脚本中的 PORT 变量。${NC}"
        exit 1
    fi
fi

# 3. 自动生成随机参数
echo -e "${GREEN}[2/6] 正在本地生成安全参数...${NC}"
UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SHORT_ID=$(openssl rand -hex 7)
SERVER_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com || curl -s --max-time 5 https://ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi
SNI="itunes.apple.com"
DEST="itunes.apple.com:443"

# 临时拉取并运行 xray 生成密钥，生成后立即删除临时镜像/容器 (不影响现有镜像)
echo -e "${BLUE}正在生成 Reality 密钥对 (使用临时容器)...${NC}"
docker pull teddysun/xray:latest > /dev/null
# 执行命令并保存输出
KEYS=$(docker run --rm teddysun/xray xray x25519)

# 提取 PrivateKey
# 匹配包含 PrivateKey 的行，按冒号分割，取第2部分，最后删除空格和换行符
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey" | awk -F ':' '{print $2}' | tr -d '[:space:]')

# 提取 PublicKey
# 匹配包含 PublicKey 的行，按冒号分割，取第2部分，最后删除空格和换行符
PUBLIC_KEY=$(echo "$KEYS" | grep "PublicKey" | awk -F ':' '{print $2}' | tr -d '[:space:]')

# 打印检查（调试用）
# echo "私钥: $PRIVATE_KEY"
# echo "公钥: $PUBLIC_KEY"

# 4. 配置文件处理
echo -e "${GREEN}[3/6] 配置服务端文件...${NC}"
CONF_DIR="/etc/docker/xray"
mkdir -p $CONF_DIR

# 备份旧配置 (如果存在)
if [ -f "$CONF_DIR/xray_reality.json" ]; then
    mv "$CONF_DIR/xray_reality.json" "$CONF_DIR/xray_reality.json.bak_$(date +%Y%m%d%H%M)"
fi

cat > $CONF_DIR/xray_reality.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# 5. 启动 Docker 容器 (仅针对本服务)
echo -e "${GREEN}[4/6] 启动专用容器...${NC}"
# 只删除本脚本相关的旧容器
docker stop xray_reality &> /dev/null
docker rm -f xray_reality &> /dev/null

docker run -d \
  --name xray_reality \
  --restart=always \
  -v $CONF_DIR/xray_reality.json:/etc/xray/config.json \
  -v /etc/localtime:/etc/localtime:ro \
  -p $PORT:$PORT \
  teddysun/xray

# 6. 生成客户端结果
VLESS_LINK="vless://$UUID@$SERVER_IP:$PORT?type=tcp&security=reality&pbk=$PUBLIC_KEY&fp=chrome&sni=$SNI&sid=$SHORT_ID&flow=xtls-rprx-vision#xray_reality_$(hostname)"

echo -e "\n${PURPLE}==================================================${NC}"
echo -e "${GREEN}安装成功！已排除系统冲突风险。${NC}"
echo -e "${PURPLE}==================================================${NC}"

echo -e "${BLUE}[1] VLESS 订阅链接:${NC}"
echo -e "$VLESS_LINK"

echo -e "\n${BLUE}[2] OpenClash 配置:${NC}"
cat <<EOF
- name: "VLESS_REALITY_$(hostname)"
  type: vless
  server: $SERVER_IP
  port: $PORT
  uuid: $UUID
  network: tcp
  flow: xtls-rprx-vision
  tls: true
  udp: true
  servername: $SNI
  reality-opts:
    public-key: $PUBLIC_KEY
    short-id: $SHORT_ID
  client-fingerprint: chrome
EOF

echo -e "\n${BLUE}[3] 扫码导入:${NC}"
qrencode -t UTF8 "$VLESS_LINK"

echo -e "${PURPLE}==================================================${NC}"
echo -e "现有 Docker 容器状态摘要:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "Names|xray_reality"
echo -e "${PURPLE}==================================================${NC}"