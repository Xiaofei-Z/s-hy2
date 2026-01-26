#!/bin/bash

# S-Hy2 服务故障诊断和修复工具

echo "🔧 S-Hy2 服务故障诊断和修复工具"
echo "=================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 判断是否为root用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
   echo "请使用: sudo $0"
   exit 1
fi

# 检查 Hysteria2 服务状态
echo -e "${BLUE}1. 检查 Hysteria2 服务状态${NC}"
echo "-------------------------------"

if systemctl is-active hysteria-server.service &>/dev/null; then
    echo -e "${GREEN}✅ Hysteria2 服务运行中${NC}"
    systemctl status hysteria-server.service --no-pager
else
    echo -e "${RED}❌ Hysteria2 服务未运行${NC}"
    systemctl status hysteria-server.service --no-pager
fi

echo ""

# 检查配置文件
echo -e "${BLUE}2. 检查配置文件${NC}"
echo "------------------"

CONFIG_FILE="/etc/hysteria/config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${GREEN}✅ 配置文件存在: $CONFIG_FILE${NC}"
    
    # 检查域名配置
    if grep -q "acme:" "$CONFIG_FILE"; then
        echo -e "${YELLOW}⚠️  检测到 ACME 证书配置${NC}"
        echo "正在分析域名配置..."
        
        # 提取域名
        domain=$(grep "domains:" "$CONFIG_FILE" | head -1 | sed 's/.*domains:[[:space:]]*//' | tr -d '[]"' | head -1)
        if [[ -n "$domain" ]]; then
            echo "配置域名: $domain"
            
            # 检查是否为示例域名
            if [[ "$domain" =~ (your\.domain\.net|example\.com) ]]; then
                echo -e "${RED}❌ 错误: 使用了示例域名${NC}"
                echo "需要修改为真实域名"
            else
                echo -e "${GREEN}✅ 域名格式检查通过${NC}"
            fi
        fi
    fi
    
    # 检查TLS配置
    if grep -q "^tls:" "$CONFIG_FILE"; then
        echo -e "${GREEN}✅ 检测到 TLS 配置（可能使用自签名证书）${NC}"
    fi
else
    echo -e "${RED}❌ 配置文件不存在: $CONFIG_FILE${NC}"
fi

echo ""

# 检查证书文件
echo -e "${BLUE}3. 检查证书文件${NC}"
echo "------------------"

CERT_DIR="/etc/hysteria/certs"
if [[ -d "$CERT_DIR" ]]; then
    cert_count=$(find "$CERT_DIR" -name "*.pem" -o -name "*.crt" -o -name "*.key" | wc -l)
    if [[ $cert_count -gt 0 ]]; then
        echo -e "${GREEN}✅ 发现 $cert_count 个证书文件${NC}"
        ls -lh "$CERT_DIR" | grep -E "\.(pem|crt|key)$"
        
        # 检查证书有效期
        echo ""
        echo "证书有效期检查:"
        for cert_file in $(find "$CERT_DIR" -name "*.pem" -o -name "*.crt"); do
            if command -v openssl &>/dev/null; then
                expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [[ -n "$expiry_date" ]]; then
                    echo "  $cert_file: $expiry_date"
                fi
            fi
        done
    else
        echo -e "${YELLOW}⚠️  证书目录为空${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  证书目录不存在${NC}"
fi

echo ""

# 检查DNS解析
echo -e "${BLUE}4. DNS 解析检查${NC}"
echo "----------------"

if [[ -n "$domain" && "$domain" != "your.domain.net" ]]; then
    echo "检查域名: $domain"
    
    # 获取服务器公网IP
    server_ip=$(curl -s --connect-timeout 5 ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null)
    
    if [[ -n "$server_ip" ]]; then
        echo "服务器IP: $server_ip"
        
        # 解析域名
        resolved_ips=$(dig +short "$domain" A 2>/dev/null)
        
        if [[ -n "$resolved_ips" ]]; then
            echo "域名解析IP:"
            echo "$resolved_ips" | while read ip; do
                if [[ "$ip" == "$server_ip" ]]; then
                    echo -e "  ${GREEN}✅ $ip (匹配)${NC}"
                else
                    echo -e "  ${YELLOW}⚠️  $ip (不匹配)${NC}"
                fi
            done
        else
            echo -e "${RED}❌ 域名无法解析${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  无法获取服务器IP${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  未配置真实域名或配置了示例域名${NC}"
fi

echo ""

# 检查端口占用
echo -e "${BLUE}5. 端口占用检查${NC}"
echo "----------------"

PORTS=(443 80)
for port in "${PORTS[@]}"; do
    if netstat -tuln | grep ":$port " | grep -q LISTEN; then
        echo -e "${GREEN}✅ 端口 $port 正在监听${NC}"
        netstat -tuln | grep ":$port " | grep LISTEN
    else
        echo -e "${YELLOW}⚠️  端口 $port 未监听${NC}"
    fi
done

echo ""

# 检查防火墙
echo -e "${BLUE}6. 防火墙检查${NC}"
echo "----------------"

if command -v firewall-cmd &>/dev/null; then
    if firewall-cmd --state &>/dev/null; then
        echo -e "${GREEN}✅ firewalld 正在运行${NC}"
        echo "开放端口:"
        firewall-cmd --list-ports 2>/dev/null || echo "无"
    else
        echo -e "${YELLOW}⚠️  firewalld 已启用但未运行${NC}"
    fi
elif command -v ufw &>/dev/null; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${GREEN}✅ UFW 正在运行${NC}"
        ufw status 2>/dev/null | head -20
    else
        echo -e "${YELLOW}⚠️  UFW 已安装但未启用${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  未检测到常见防火墙${NC}"
fi

echo ""

# 提供修复建议
echo -e "${BLUE}7. 修复建议${NC}"
echo "-------------"

# 读取服务状态判断问题
SERVICE_STATUS=$(systemctl is-active hysteria-server.service 2>/dev/null)

if [[ "$SERVICE_STATUS" != "active" ]]; then
    echo -e "${RED}服务未运行，可能原因：${NC}"
    
    # 检查日志中的错误
    if journalctl -u hysteria-server.service --no-pager -n 20 2>/dev/null | grep -q "rateLimited"; then
        echo -e "${YELLOW}🔴 ACME 证书限制问题${NC}"
        echo ""
        echo "这是因为 Let's Encrypt 检测到多次失败的证书申请，建议："
        echo "1. 等待 1 小时后重试"
        echo "2. 使用自签名证书方案"
        echo "3. 确保域名 DNS 正确配置"
        echo "4. 检查防火墙是否开放 80/443 端口"
    fi
    
    if journalctl -u hysteria-server.service --no-pager -n 20 2>/dev/null | grep -q "your.domain.net"; then
        echo ""
        echo -e "${YELLOW}🔴 使用了示例域名${NC}"
        echo "需要修改配置文件，将 'your.domain.net' 替换为真实域名"
    fi
fi

echo ""
echo -e "${GREEN}诊断完成${NC}"
echo ""
echo "下一步操作建议:"
echo "1. 如果是域名问题，修改配置文件中的域名"
echo "2. 如果是ACME限制，等待1小时或使用自签名证书"
echo "3. 检查DNS解析和防火墙配置"
echo "4. 重新启动服务: systemctl restart hysteria-server"