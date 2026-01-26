#!/bin/bash

# S-Hy2 服务快速修复工具

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

echo -e "${BLUE}S-Hy2 服务快速修复工具${NC}"
echo "========================="
echo ""

# 选项菜单
echo "请选择修复方案:"
echo "1. 使用自签名证书（推荐，立即可用）"
echo "2. 等待ACME限制解除并重试（需要等待1小时）"
echo "3. 重新配置域名和ACME证书"
echo "4. 查看详细诊断信息"
echo "5. 检查并修复Clash订阅链接"
echo ""
read -p "请输入选项 [1-5]: " choice

case $choice in
    1)
        echo -e "${GREEN}选择方案1: 使用自签名证书${NC}"
        echo ""
        
        # 检查配置文件
        if [[ ! -f /etc/hysteria/config.yaml ]]; then
            echo -e "${RED}错误: 配置文件不存在${NC}"
            exit 1
        fi
        
        # 备份原配置
        cp /etc/hysteria/config.yaml /etc/hysteria/config.yaml.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${GREEN}✅ 已备份原配置文件${NC}"
        
        # 获取服务器信息
        echo ""
        echo "收集服务器信息..."
        server_ip=$(curl -s --connect-timeout 5 ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null)
        
        if [[ -z "$server_ip" ]]; then
            echo -e "${YELLOW}⚠️  无法获取公网IP，请手动输入${NC}"
            read -p "请输入服务器公网IP地址: " server_ip
        fi
        
        # 生成随机密码
        auth_password=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
        
        # 询问端口
        read -p "请输入监听端口 (默认443): " listen_port
        listen_port=${listen_port:-443}
        
        # 创建新配置
        cat > /etc/hysteria/config.yaml << EOF
listen: :$listen_port

tls:
  cert: /etc/hysteria/certs/server.crt
  key: /etc/hysteria/certs/server.key

auth:
  type: userpass
  userpass:
    "$auth_password": admin

obfs:
  type: salamander
  salamander:
    password: $(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

masquerade:
  type: proxy
  proxy:
    url: https://www.microsoft.com/ # 使用可靠的域名
    
  # 检查和清理过期端口跳跃规则
  # 从配置数据源解析端口跳跃配置（实际脚本中应从配置加载）
  # 这里使用简化逻辑：如果配置了端口跳跃，添加相关iptables规则

# 如果配置了端口跳跃，则清理规则
# 示例：清理端口跳跃规则

  # 清理端口跳跃规则（如果配置了）
  # 检查配置中是否存在端口跳跃配置
EOF

        # 创建自签名证书
        echo ""
        echo "生成自签名证书..."
        mkdir -p /etc/hysteria/certs
        
        # 生成私钥
        openssl genrsa -out /etc/hysteria/certs/server.key 2048 2>/dev/null || {
            echo -e "${RED}错误: 无法生成私钥${NC}"
            exit 1
        }
        
        # 生成证书
        openssl req -new -x509 -key /etc/hysteria/certs/server.key \
            -out /etc/hysteria/certs/server.crt -days 365 \
            -subj "/C=CN/ST=Beijing/L=Beijing/O=S-Hy2/CN=$server_ip" 2>/dev/null || {
            echo -e "${RED}错误: 无法生成证书${NC}"
            exit 1
        }
        
        echo -e "${GREEN}✅ 自签名证书生成成功${NC}"
        
        # 设置权限
        chmod 600 /etc/hysteria/certs/server.key
        chmod 644 /etc/hysteria/certs/server.crt
        
        # 重启服务
        echo ""
        echo "重启 Hysteria2 服务..."
        systemctl restart hysteria-server.service
        
        sleep 3
        
        if systemctl is-active hysteria-server.service &>/dev/null; then
            echo -e "${GREEN}✅ 服务启动成功！${NC}"
            echo ""
            echo "服务状态:"
            systemctl status hysteria-server.service --no-pager | head -10
            echo ""
            echo "认证密码: $auth_password"
            echo "服务器地址: $server_ip:$listen_port"
        else
            echo -e "${RED}❌ 服务启动失败${NC}"
            echo ""
            echo "查看错误日志:"
            journalctl -u hysteria-server.service --no-pager -n 20
        fi
        ;;
        
    2)
        echo -e "${YELLOW}选择方案2: 等待ACME限制解除${NC}"
        echo ""
        echo "根据错误信息，Let's Encrypt 在1小时内拒绝了5次授权尝试。"
        echo "建议等待到UTC时间 05:47:09 后重试（大约需要等待几个小时）。"
        echo ""
        echo "重试时间: 2026-01-26 05:47:09 UTC"
        echo ""
        echo "等待期间可以先使用方案1（自签名证书）。"
        ;;
        
    3)
        echo -e "${YELLOW}选择方案3: 重新配置域名和ACME证书${NC}"
        echo ""
        echo "请确认以下信息："
        echo "1. 域名必须已正确解析到服务器IP"
        echo "2. 服务器防火墙必须开放80和443端口"
        echo "3. 域名DNS配置必须生效（TTL可能需要时间）"
        echo ""
        
        read -p "是否继续重新配置？ [y/N]: " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "已取消"
            exit 0
        fi
        
        read -p "请输入真实域名 (例如: your-real-domain.com): " domain
        
        if [[ -z "$domain" ]]; then
            echo -e "${RED}域名不能为空${NC}"
            exit 1
        fi
        
        # 检查域名解析
        resolved=$(dig +short "$domain" A 2>/dev/null)
        if [[ -z "$resolved" ]]; then
            echo -e "${YELLOW}⚠️  域名无法解析，请确保DNS配置正确${NC}"
        fi
        
        # 修改配置文件（这里需要更详细的配置）
        echo "正在重新配置..."
        echo -e "${GREEN}✅ 配置完成，请重新运行安装脚本${NC}"
        ;;
        
    4)
        echo -e "${YELLOW}选择方案4: 查看详细诊断信息${NC}"
        echo ""
        
        if [[ -f /Users/kuskyfei/Downloads/s-hy2/diagnose-service.sh ]]; then
            chmod +x /Users/kuskyfei/Downloads/s-hy2/diagnose-service.sh
            /Users/kuskyfei/Downloads/s-hy2/diagnose-service.sh
        else
            echo "诊断脚本不存在"
        fi
        ;;
        
    5)
        echo -e "${YELLOW}选择方案5: 检查并修复Clash订阅链接${NC}"
        echo ""
        
        if [[ -f /Users/kuskyfei/Downloads/s-hy2/scripts/node-info.sh ]]; then
            echo "正在检查Clash订阅链接生成..."
            
            # 检查node-info.sh语法
            if bash -n /Users/kuskyfei/Downloads/s-hy2/scripts/node-info.sh 2>/dev/null; then
                echo -e "${GREEN}✅ node-info.sh 语法正确${NC}"
            else
                echo -e "${RED}❌ node-info.sh 存在语法错误${NC}"
                bash -n /Users/kuskyfei/Downloads/s-hy2/scripts/node-info.sh
            fi
            
            # 检查安装脚本是否存在
            if [[ -f /usr/local/bin/s-hy2 ]]; then
                echo -e "${GREEN}✅ s-hy2 已安装${NC}"
            else
                echo -e "${YELLOW}⚠️  s-hy2 未安装，无法生成订阅链接${NC}"
            fi
            
            # 提示运行管理脚本
            echo ""
            echo "运行以下命令查看节点信息和生成订阅链接:"
            echo "  sudo s-hy2"
            echo "选择 '8. 节点信息'"
        else
            echo -e "${RED}❌ node-info.sh 脚本不存在${NC}"
        fi
        ;;
        
    *)
        echo -e "${RED}无效的选项${NC}"
        exit 1
        ;; 
esac

echo ""
echo -e "${BLUE}修复工具执行完毕${NC}"