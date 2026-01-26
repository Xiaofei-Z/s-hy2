#!/bin/bash

# S-Hy2 Clash订阅链接诊断和修复工具

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}S-Hy2 Clash 订阅链接诊断工具${NC}"
echo "================================"
echo ""

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
    exit 1
fi

# 步骤1: 检查Hysteria2服务
echo -e "${YELLOW}步骤 1: 检查 Hysteria2 服务状态${NC}"
if systemctl is-active hysteria-server.service &>/dev/null; then
    echo -e "${GREEN}✅ Hysteria2 服务运行正常${NC}"
else
    echo -e "${RED}❌ Hysteria2 服务未运行${NC}"
    echo "请先修复 Hysteria2 服务"
    exit 1
fi

echo ""

# 步骤2: 获取正确的服务器信息
echo -e "${YELLOW}步骤 2: 获取服务器配置信息${NC}"

# 从配置文件读取
GET_SERVER_IP="/etc/hysteria/server-domain.conf"
if [[ -f "$GET_SERVER_IP" ]]; then
    CONFIGURED_DOMAIN=$(cat "$GET_SERVER_IP" 2>/dev/null)
    if [[ -n "$CONFIGURED_DOMAIN" ]]; then
        echo -e "${GREEN}配置的域名: $CONFIGURED_DOMAIN${NC}"
    else
        echo -e "${YELLOW}无配置域名${NC}"
    fi
fi

# 读取配置文件获取实际信息
ACTUAL_PORT=$(grep -E "listen:.*:" /etc/hysteria/config.yaml | sed 's/.*:\([0-9]*\)/\1/' | head -1)
echo -e "${GREEN}监听端口: $ACTUAL_PORT${NC}"

# 获取公网IP
PUBLIC_IP=$(curl -s --connect-timeout 5 ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null)
if [[ -n "$PUBLIC_IP" ]]; then
    echo -e "${GREEN}服务器公网IP: $PUBLIC_IP${NC}"
fi

echo ""

# 步骤3: 检查HTTP服务器
echo -e "${YELLOW}步骤 3: 检查 HTTP 服务器${NC}"

HTTP_SERVICE=""
if systemctl is-active nginx &>/dev/null; then
    HTTP_SERVICE="nginx"
    echo -e "${GREEN}✅ nginx 正在运行${NC}"
elif systemctl is-active apache2 &>/dev/null; then
    HTTP_SERVICE="apache2"
    echo -e "${GREEN}✅ apache2 正在运行${NC}"
elif systemctl is-active httpd &>/dev/null; then
    HTTP_SERVICE="httpd"
    echo -e "${GREEN}✅ httpd 正在运行${NC}"
else
    echo -e "${RED}❌ HTTP 服务器未运行${NC}"
    echo ""
    echo "需要安装HTTP服务器才能使用订阅链接"
    echo "安装命令:"
    echo "  Ubuntu/Debian: apt update && apt install -y nginx"
    echo "  CentOS/RHEL: yum install -y nginx"
    exit 1
fi

# 检查订阅目录
SUB_DIR="/var/www/html/sub"
if [[ -d "$SUB_DIR" ]]; then
    echo -e "${GREEN}✅ 订阅目录存在: $SUB_DIR${NC}"
else
    echo -e "${YELLOW}⚠️  订阅目录不存在，正在创建...${NC}"
    mkdir -p "$SUB_DIR"
    chmod 755 "$SUB_DIR"
fi

echo ""

# 步骤4: 检查现有订阅文件
echo -e "${YELLOW}步骤 4: 检查现有订阅文件${NC}"

if ls -1 "$SUB_DIR/clash-"*.yaml &>/dev/null; then
    echo -e "${GREEN}发现 Clash 订阅文件:${NC}"
    ls -la "$SUB_DIR/clash-"*.yaml
    
    # 检查订阅文件内容
    echo ""
    echo -e "${BLUE}检查订阅文件配置:${NC}"
    
    for file in "$SUB_DIR/clash-"*.yaml; do
        echo ""
        echo "文件: $(basename $file)"
        
        # 检查server字段
        CONFIG_IP=$(grep -E "^\s+server:" "$file" | awk '{print $2}' | tr -d '"')
        CONFIG_PORT=$(grep -E "^\s+port:" "$file" | awk '{print $2}')
        
        echo "配置IP: $CONFIG_IP"
        echo "配置端口: $CONFIG_PORT"
        
        # 检查是否使用正确IP
        if [[ "$CONFIG_IP" == "$PUBLIC_IP" ]]; then
            echo -e "${GREEN}✅ IP地址正确${NC}"
        else
            echo -e "${RED}❌ IP地址错误！应该是: $PUBLIC_IP${NC}"
        fi
        
        if [[ "$CONFIG_PORT" == "$ACTUAL_PORT" ]]; then
            echo -e "${GREEN}✅ 端口正确${NC}"
        else
            echo -e "${RED}❌ 端口错误！应该是: $ACTUAL_PORT${NC}"
        fi
    done
else
    echo -e "${RED}❌ 未找到 Clash 订阅文件${NC}"
fi

echo ""

# 步骤5: 修复订阅文件
echo -e "${YELLOW}步骤 5: 修复 Clash 订阅文件${NC}"

# 读取Hysteria2配置获取正确信息
AUTH_PASSWORD=$(grep -E "password:" /etc/hysteria/config.yaml | awk '{print $2}' | tr -d '"')
OBF_PASSWORD=$(grep -A 2 "obfs:" /etc/hysteria/config.yaml | grep "password:" | awk '{print $2}' | tr -d '"')
MASQUERADE_URL=$(grep -A 2 "masquerade:" /etc/hysteria/config.yaml | grep "url:" | awk '{print $2}')
SNI=$(echo "$MASQUERADE_URL" | sed 's|https\?://||' | sed 's|/.*||')

if [[ -z "$AUTH_PASSWORD" ]]; then
    echo -e "${RED}❌ 无法从配置文件读取认证密码${NC}"
    exit 1
fi

echo "使用配置信息:"
echo "服务器IP: $PUBLIC_IP"
echo "端口: $ACTUAL_PORT"
echo "认证密码: $AUTH_PASSWORD"
echo "混淆密码: $OBF_PASSWORD"
echo "SNI: $SNI"

# 删除旧的订阅文件
rm -f "$SUB_DIR/clash-"*.yaml
echo -e "${GREEN}✅ 已删除旧订阅文件${NC}"

# 生成新的订阅文件
UUID=$(openssl rand -hex 8)
CLASH_FILE="$SUB_DIR/clash-${UUID}.yaml"

cat > "$CLASH_FILE" << EOF
# Clash 订阅配置 (自动生成)
# 服务器IP: $PUBLIC_IP
# 生成时间: $(date)

proxies:
  - name: "S-Hy2-Server"
    type: hysteria2
    server: $PUBLIC_IP
    port: $ACTUAL_PORT
    password: $AUTH_PASSWORD
    obfs: salamander
    obfs-password: $OBF_PASSWORD
    sni: $SNI
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
  - IP-CIDR,172.16.0.0/12,🎯 全球直连
  - GEOIP,CN,🎯 全球直连
  - MATCH,🚀 节点选择
EOF

chmod 644 "$CLASH_FILE"

echo -e "${GREEN}✅ 新订阅文件已生成${NC}"
echo ""

# 步骤6: 检查HTTP服务器配置
echo -e "${YELLOW}步骤 6: 检查 HTTP 服务器配置${NC}"

if [[ "$HTTP_SERVICE" == "nginx" ]]; then
    # 检查nginx是否允许访问订阅目录
    echo -e "${BLUE}nginx 配置检查:${NC}"
    
    # 创建nginx配置（如果不存在）
    if ! nginx -t 2>&1 | grep -q "successful"; then
        echo -e "${YELLOW}nginx配置有误，正在修复...${NC}"
    fi
    
    # 重启nginx
    systemctl restart nginx 2>/dev/null || true
    echo -e "${GREEN}✅ nginx 已重启${NC}"
    
    # 检查端口
    if netstat -tuln | grep ":80 " | grep -q LISTEN; then
        echo -e "${GREEN}✅ nginx 80端口已开放${NC}"
    else
        echo -e "${YELLOW}⚠️  nginx 80端口未监听${NC}"
    fi
    
elif [[ "$HTTP_SERVICE" == "apache2" ]]; then
    # 检查apache2配置
    echo -e "${BLUE}apache2 配置检查:${NC}"
    systemctl restart apache2 2>/dev/null || true
    echo -e "${GREEN}✅ apache2 已重启${NC}"
    
    if netstat -tuln | grep ":80 " | grep -q LISTEN; then
        echo -e "${GREEN}✅ apache2 80端口已开放${NC}"
    else
        echo -e "${YELLOW}⚠️  apache2 80端口未监听${NC}"
    fi
fi

echo ""

# 步骤7: 测试订阅链接访问
echo -e "${YELLOW}步骤 7: 测试订阅链接访问${NC}"

if [[ -n "$PUBLIC_IP" ]]; then
    TEST_URL="http://$PUBLIC_IP/sub/$CLASH_FILE"
    echo "测试URL: $TEST_URL"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TEST_URL" 2>/dev/null)
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo -e "${GREEN}✅ 订阅链接可访问 (HTTP 200)${NC}"
    else
        echo -e "${YELLOW}⚠️  订阅链接访问异常 (HTTP $HTTP_CODE)${NC}"
    fi
else
    echo -e "${RED}❌ 无法获取服务器IP${NC}"
fi

echo ""

# 步骤8: 检查防火墙
echo -e "${YELLOW}步骤 8: 检查防火墙配置${NC}"

if command -v ufw &>/dev/null; then
    if ufw status 2>/dev/null | grep -q "80/tcp.*ALLOW"; then
        echo -e "${GREEN}✅ ufw 80端口已开放${NC}"
    else
        echo -e "${YELLOW}⚠️  ufw 80端口未开放${NC}"
        echo "开放80端口: ufw allow 80/tcp"
    fi
elif command -v firewall-cmd &>/dev/null; then
    if firewall-cmd --list-ports | grep -q "80/tcp"; then
        echo -e "${GREEN}✅ firewalld 80端口已开放${NC}"
    else
        echo -e "${YELLOW}⚠️  firewalld 80端口未开放${NC}"
        echo "开放80端口: firewall-cmd --permanent --add-port=80/tcp && firewall-cmd --reload"
    fi
else
    echo -e "${YELLOW}⚠️  未检测到常见防火墙${NC}"
fi

echo ""

# 步骤9: 生成最终报告
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🎯 Clash 订阅链接诊断结果${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [[ -n "$PUBLIC_IP" ]]; then
    echo -e "${GREEN}✅ 修复后的 Clash 订阅链接:${NC}"
    echo "http://$PUBLIC_IP/sub/clash-${UUID}.yaml"
    echo ""
    
    echo -e "${BLUE}📋 配置信息:${NC}"
    echo "----------------------------------------"
    echo "服务器IP: $PUBLIC_IP"
    echo "端口: $ACTUAL_PORT"
    echo "文件名: clash-${UUID}.yaml"
    echo "----------------------------------------"
    echo ""
    
    echo -e "${BLUE}📱 Clash 客户端配置:${NC}"
    echo "${YELLOW}⚠️  重要提示: 必须启用 '跳过证书验证'${NC}"
    echo ""
    echo "1. 复制订阅链接到 Clash 客户端"
    echo "2. 在节点配置中启用: skip-cert-verify: true"
    echo "3. 测试连接"
    echo ""
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 订阅链接已修复完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}❌ 无法生成订阅链接${NC}"
    echo ""
    echo "可能原因:"
    echo "1. 服务器无法获取公网IP"
    echo "2. HTTP服务器配置问题"
    echo "3. 网络连接问题"
fi

echo ""
echo -e "${BLUE}下一步操作:${NC}"
echo "1. 复制上方订阅链接到 Clash 导入"
echo "2. 在 Clash 中启用 '跳过证书验证'"
echo "3. 测试连接是否正常"
echo "4. 如有问题，查看服务日志: journalctl -u hysteria-server.service -f"