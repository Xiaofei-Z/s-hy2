#!/bin/bash

# S-Hy2 自签名证书修复工具 (无需真实域名)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
   exit 1
fi

echo -e "${BLUE}S-Hy2 自签名证书自动修复工具${NC}"
echo "================================="
echo ""

# 步骤1: 停止当前服务
echo -e "${YELLOW}步骤 1: 停止 Hysteria2 服务${NC}"
systemctl stop hysteria-server.service 2>/dev/null
echo -e "${GREEN}✅ 服务已停止${NC}"

# 步骤2: 获取服务器信息
echo ""
echo -e "${YELLOW}步骤 2: 收集服务器信息${NC}"

# 获取公网IP
server_ip=$(curl -s --connect-timeout 5 ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null)

if [[ -z "$server_ip" ]]; then
    echo -e "${RED}无法获取公网IP${NC}"
    read -p "请输入服务器公网IP地址: " server_ip
    
    if [[ -z "$server_ip" ]]; then
        echo -e "${RED}IP地址不能为空${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ 服务器IP: $server_ip${NC}"

# 生成随机认证密码
auth_password=$(openssl rand -base24 | tr -d "=+/" | cut -c1-24)
echo -e "${GREEN}✅ 认证密码已生成: $auth_password${NC}"

# 生成随机混淆密码
obfs_password=$(openssl rand -base24 | tr -d "=+/" | cut -c1-24)
echo -e "${GREEN}✅ 混淆密码已生成: $obfs_password${NC}"

# 步骤3: 创建证书目录
echo ""
echo -e "${YELLOW}步骤 3: 创建证书目录${NC}"
mkdir -p /etc/hysteria/certs
chmod 700 /etc/hysteria/certs
echo -e "${GREEN}✅ 证书目录已创建${NC}"

# 步骤4: 生成自签名证书
echo ""
echo -e "${YELLOW}步骤 4: 生成自签名证书${NC}"

# 生成私钥
openssl genrsa -out /etc/hysteria/certs/server.key 2048 2>/dev/null

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ 私钥生成失败${NC}"
    exit 1
fi

# 生成证书
openssl req -new -x509 -key /etc/hysteria/certs/server.key \
    -out /etc/hysteria/certs/server.crt -days 3650 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=S-Hy2/CN=$server_ip" \
    -extensions SAN -config <(cat /etc/ssl/openssl.cnf <(echo "[SAN]"; echo "subjectAltName=IP:$server_ip,DNS:$server_ip")) 2>/dev/null

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ 自签名证书生成成功${NC}"
else
    echo -e "${YELLOW}⚠️  基础证书生成成功 (SAN扩展需要 OpenSSL 1.1.1+ )${NC}"
    # 尝试基础生成（不带SAN扩展）
    openssl req -new -x509 -key /etc/hysteria/certs/server.key \
        -out /etc/hysteria/certs/server.crt -days 3650 \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=S-Hy2/CN=$server_ip" 2>/dev/null
fi

# 设置权限
chmod 600 /etc/hysteria/certs/server.key
chmod 644 /etc/hysteria/certs/server.crt
echo -e "${GREEN}✅ 证书权限已设置${NC}"

# 步骤5: 备份原配置
echo ""
echo -e "${YELLOW}步骤 5: 备份原配置文件${NC}"
if [[ -f /etc/hysteria/config.yaml ]]; then
    cp /etc/hysteria/config.yaml /etc/hysteria/config.yaml.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}✅ 配置文件已备份${NC}"
else
    echo -e "${YELLOW}⚠️  配置文件不存在，将创建新配置${NC}"
fi

# 步骤6: 询问配置选项
echo ""
echo -e "${YELLOW}步骤 6: 配置服务参数${NC}"

# 监听端口
read -p "请输入监听端口 (默认443): " listen_port
listen_port=${listen_port:-443}
echo -e "${GREEN}监听端口: $listen_port${NC}"

# 伪装域名
read -p "请输入伪装域名 (默认使用www.microsoft.com): " masquerade
masquerade=${masquerade:-www.microsoft.com}
echo -e "${GREEN}伪装域名: $masquerade${NC}"

# 上行带宽
read -p "请输入上行带宽 (MB/s，默认100): " up_bandwidth
up_bandwidth=${up_bandwidth:-100}
echo -e "${GREEN}上行带宽: ${up_bandwidth} MB/s${NC}"

# 下行带宽
read -p "请输入下行带宽 (MB/s，默认100): " down_bandwidth
down_bandwidth=${down_bandwidth:-100}
echo -e "${GREEN}下行带宽: ${down_bandwidth} MB/s${NC}"

# 步骤7: 创建新配置文件
echo ""
echo -e "${YELLOW}步骤 7: 创建配置文件${NC}"

cat > /etc/hysteria/config.yaml << EOF
# S-Hy2 配置文件 (自签名证书)
listen: :$listen_port

# TLS 配置 (使用自签名证书)
tls:
  cert: /etc/hysteria/certs/server.crt
  key: /etc/hysteria/certs/server.key

# 认证配置
auth:
  type: userpass
  userpass:
    "$auth_password": admin

# 混淆配置
obfs:
  type: salamander
  salamander:
    password: $obfs_password

# 伪装配置
masquerade:
  type: proxy
  proxy:
    url: https://$masquerade/
    rewriteHost: true

# 带宽配置
bandwidth:
  up: ${up_bandwidth} mbps
  down: ${down_bandwidth} mbps

# 忽略证书验证的IPv4地址范围
skipCertVerify:
  type: CIDRList
  fallback: false

# 快速连接设置
fastOpen:
  udp: true

# ICMP/v4/v6 支持
icmp:
  type: reject
EOF

echo -e "${GREEN}✅ 配置文件创建成功${NC}"

# 步骤8: 保存连接信息
echo ""
echo -e "${YELLOW}步骤 8: 保存连接信息${NC}"

cat > /etc/hysteria/node-info.txt << EOF
S-Hy2 节点信息
===============

连接配置:
服务器地址: $server_ip
监听端口: $listen_port
认证密码: $auth_password
混淆密码: $obfs_password
证书: 自签名证书

Hysteria2 原生链接:
hysteria2://$auth_password@$server_ip:$listen_port?insecure=1&obfs=salamander&obfs-password=$obfs_password&sni=$masquerade#S-Hy2-Node

客户端配置:
- 需要在客户端中启用"跳过证书验证"
- 伪装SNI: $masquerade

生成时间: $(date)
EOF

chmod 644 /etc/hysteria/node-info.txt
echo -e "${GREEN}✅ 连接信息已保存${NC}"

# 步骤9: 刷新systemd
echo ""
echo -e "${YELLOW}步骤 9: 刷新systemd配置${NC}"
systemctl daemon-reload
echo -e "${GREEN}✅ systemd配置已刷新${NC}"

# 步骤10: 启动服务
echo ""
echo -e "${YELLOW}步骤 10: 启动 Hysteria2 服务${NC}"

systemctl start hysteria-server.service
sleep 3

if systemctl is-active hysteria-server.service &>/dev/null; then
    echo -e "${GREEN}✅ 服务启动成功！${NC}"
    
    # 显示服务状态
    echo ""
    echo -e "${BLUE}服务状态:${NC}"
    systemctl status hysteria-server.service --no-pager | head -15
    
    # 显示连接信息
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 S-Hy2 服务配置完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}📋 连接信息:${NC}"
    echo "----------------------------------------"
    echo "服务器地址: $server_ip:$listen_port"
    echo "认证密码: $auth_password"
    echo "混淆密码: $obfs_password"
    echo "伪装SNI: $masquerade"
    echo "证书类型: 自签名证书"
    echo "----------------------------------------"
    echo ""
    echo -e "${BLUE}📱 Hysteria2 原生链接:${NC}"
    echo "hysteria2://$auth_password@$server_ip:$listen_port?insecure=1&obfs=salamander&obfs-password=$obfs_password&sni=$masquerade#S-Hy2-Node"
    echo ""
    echo -e "${BLUE}⚠️  重要提示:${NC}"
    echo "----------------------------------------"
    echo "1. 客户端需要启用 '跳过证书验证' 或 '不安全连接'"
    echo "2. 在 Clash 中设置: skip-cert-verify: true"
    echo "3. 在 SNI 字段填入: $masquerade"
    echo "----------------------------------------"
    echo ""
    echo -e "${GREEN}✅ 服务已成功启动并运行！${NC}"
    echo ""
    echo -e "${BLUE}查看完整日志:${NC}"
    echo "journalctl -u hysteria-server.service -f"
    echo ""
    echo -e "${BLUE}查看连接信息:${NC}"
    echo "cat /etc/hysteria/node-info.txt"
    
    # 询问是否配置Clash订阅
    echo ""
    read -p "是否现在生成 Clash 订阅链接？ [y/N]: " generate_clash
    
    if [[ $generate_clash =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}配置 Clash 订阅链接...${NC}"
        
        # 检查HTTP服务器
        if command -v nginx &>/dev/null || command -v apache2 &>/dev/null; then
            echo -e "${GREEN}✅ 检测到HTTP服务器${NC}"
            
            # 创建订阅目录
            mkdir -p /var/www/html/sub
            chmod 755 /var/www/html/sub
            
            # 启动HTTP服务器
            if command -v nginx &>/dev/null; then
                systemctl start nginx 2>/dev/null || true
                systemctl enable nginx 2>/dev/null || true
            fi
            
            # 生成Clash配置
            uuid=$(openssl rand -hex 8)
            clash_file="/var/www/html/sub/clash-${uuid}.yaml"
            
            cat > "$clash_file" << EOF
proxies:
  - name: "S-Hy2-Server"
    type: hysteria2
    server: $server_ip
    port: $listen_port
    password: $auth_password
    obfs: salamander
    obfs-password: $obfs_password
    sni: $masquerade
    skip-cert-verify: true
    alpn:
      - h3

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "S-Hy2-Server"
  
  - name: "🎯 全球直连"
    type: select
    proxies:
      - "DIRECT"

rules:
  - DOMAIN-SUFFIX,local,🎯 全球直连
  - IP-CIDR,192.168.0.0/16,🎯 全球直连
  - IP-CIDR,10.0.0.0/8,🎯 全球直连
  - GEOIP,CN,🎯 全球直连
  - MATCH,🚀 节点选择
EOF
            
            chmod 644 "$clash_file"
            
            echo ""
            echo -e "${GREEN}✅ Clash 订阅链接已生成${NC}"
            echo ""
            echo -e "${BLUE}📱 Clash 订阅链接:${NC}"
            echo "http://$server_ip/sub/clash-${uuid}.yaml"
            echo ""
            echo -e "${BLUE}📝 使用说明:${NC}"
            echo "1. 复制上方链接"
            echo "2. 在 Clash 客户端中添加订阅"
            echo "3. 确保客户端启用了 '跳过证书验证'"
        else
            echo -e "${YELLOW}⚠️  未检测到HTTP服务器，跳过订阅链接生成${NC}"
            echo "安装HTTP服务器: apt install nginx 或 yum install nginx"
        fi
    fi
    
else
    echo -e "${RED}❌ 服务启动失败${NC}"
    echo ""
    echo -e "${YELLOW}查看错误日志:${NC}"
    journalctl -u hysteria-server.service --no-pager -n 30
    echo ""
    echo -e "${YELLOW}检查配置文件:${NC}"
    cat /etc/hysteria/config.yaml
    exit 1
fi