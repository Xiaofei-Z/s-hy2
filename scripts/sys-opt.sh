#!/bin/bash

# 系统性能优化脚本
# 用于 Hysteria 2 的系统内核参数优化 (BBR, Sysctl)

# 引用公共函数库
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Sysctl 配置文件路径
SYSCTL_CONF="/etc/sysctl.d/99-hysteria.conf"
LIMITS_CONF="/etc/security/limits.d/hysteria.conf"

# 应用 Sysctl 优化
apply_sysctl_optimizations() {
    echo ""
    log_info "正在应用 Sysctl 网络优化..."
    
    # 加载必要的内核模块 (用于 conntrack 优化)
    modprobe nf_conntrack 2>/dev/null
    
    # 检测系统内存
    local mem_total_kb
    mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "2000000")
    local mem_total_mb=$((mem_total_kb / 1024))
    
    log_info "检测到系统内存: ${mem_total_mb}MB"
    
    # 动态设置参数
    local rmem_max
    local wmem_max
    local rmem_default
    local wmem_default
    local backlog
    local conntrack_max
    
    if [[ "$mem_total_mb" -lt 1500 ]]; then
        # 内存小于 1.5GB (如 1GB 机器)
        # 针对 10+ 客户端连接优化：
        # 1. 缓冲区保持保守以防 OOM
        # 2. Conntrack 表适当控制，避免占用过多内核内存 (每条记录约 300字节)
        log_warn "内存较小 (<1.5GB)，将应用适合多客户端并发的保守配置"
        rmem_max=8388608      # 8MB
        wmem_max=8388608      # 8MB
        rmem_default=2097152  # 2MB
        wmem_default=2097152  # 2MB
        backlog=10000         # 降低队列长度
        conntrack_max=65536   # 64k 连接数 (约占用 20MB 内存)
    else
        # 内存充足 (>= 1.5GB)
        log_info "内存充足，将应用高性能并发配置"
        rmem_max=33554432     # 32MB
        wmem_max=33554432     # 32MB
        rmem_default=8388608  # 8MB
        wmem_default=8388608  # 8MB
        backlog=50000
        conntrack_max=262144  # 262k 连接数
    fi
    
    # 1. 备份现有配置
    if [[ -f /etc/sysctl.conf ]]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%F-%T)"
        log_debug "已备份 /etc/sysctl.conf"
    fi
    
    # 2. 写入 Hysteria 专用配置
    cat > "$SYSCTL_CONF" <<EOF
# Hysteria 2 Performance Tuning
# 自动生成的配置 (内存: ${mem_total_mb}MB, 目标: 多客户端并发优化)

# --- UDP 缓冲区优化 (核心) ---
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.core.rmem_default = $rmem_default
net.core.wmem_default = $wmem_default

# --- 并发连接数与队列优化 ---
# 增加网络设备积压队列长度
net.core.netdev_max_backlog = $backlog
# 增加监听队列上限 (防止突发连接丢失)
net.core.somaxconn = 65535

# --- 连接追踪 (Conntrack) 优化 ---
# 针对多客户端 (10+) 场景，防止连接表溢出
net.netfilter.nf_conntrack_max = $conntrack_max
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
# 缩短 UDP 追踪超时，加速回收资源 (Hy2 使用 UDP)
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 120

# --- TCP/BBR 优化 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 常规网络栈增强 ---
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
# 扩大本地端口范围，支持更多出站连接
net.ipv4.ip_local_port_range = 1024 65535
# 增加 ARP 缓存表大小 (防止多客户端导致 ARP 溢出)
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
EOF
    log_info "已创建配置文件: $SYSCTL_CONF"

    # 3. 应用更改
    if sysctl --system >/dev/null 2>&1; then
        log_success "网络内核参数优化成功"
    else
        log_warn "网络内核参数应用可能不完整，建议重启服务器"
    fi
}

# 优化文件描述符限制
optimize_ulimit() {
    echo ""
    log_info "正在优化文件描述符限制..."
    
    # 1. 系统级限制
    cat > "$LIMITS_CONF" <<EOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    log_info "已更新系统限制: $LIMITS_CONF"

    # 2. 针对 Systemd 服务的限制
    if [[ -f "/etc/systemd/system/hysteria-server.service" ]]; then
        if ! grep -q "LimitNOFILE" /etc/systemd/system/hysteria-server.service; then
            # 在 [Service] 块后添加 LimitNOFILE
            sed -i '/\[Service\]/a LimitNOFILE=1048576' /etc/systemd/system/hysteria-server.service
            systemctl daemon-reload
            log_success "已添加 LimitNOFILE 到服务配置"
            
            # 询问重启
            echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
            read -r restart
            if [[ ! $restart =~ ^[Nn]$ ]]; then
                systemctl restart hysteria-server
                log_success "服务已重启"
            fi
        else
            log_info "服务配置中已存在 LimitNOFILE"
        fi
    fi
}

# 检查 BBR 状态
check_bbr_status() {
    local bbr_status
    bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qdisc_status
    qdisc_status=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    echo -e "${CYAN}当前 BBR 状态:${NC}"
    if [[ "$bbr_status" == *"bbr"* ]]; then
        echo -e "TCP 拥塞控制: ${GREEN}$bbr_status (已开启)${NC}"
    else
        echo -e "TCP 拥塞控制: ${YELLOW}$bbr_status (未开启)${NC}"
    fi
    
    if [[ "$qdisc_status" == *"fq"* ]]; then
        echo -e "队列算法: ${GREEN}$qdisc_status (已开启)${NC}"
    else
        echo -e "队列算法: ${YELLOW}$qdisc_status${NC}"
    fi
}

# 验证优化结果
verify_optimization() {
    echo ""
    echo -e "${CYAN}=== 优化结果验证 ===${NC}"
    
    # 检查 rmem_max
    local rmem
    rmem=$(sysctl -n net.core.rmem_max 2>/dev/null)
    # 检测内存以决定标准
    local mem_kb
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "2000000")
    local target_buffer=33554432
    if [[ "$((mem_kb/1024))" -lt 1500 ]]; then
        target_buffer=8388608
    fi

    if [[ "$rmem" -ge "$target_buffer" ]]; then
        echo -e "UDP 接收缓冲区: ${GREEN}✅ 已优化 ($rmem)${NC}"
    else
        echo -e "UDP 接收缓冲区: ${YELLOW}⚠️  未达标 (当前: $rmem, 目标: $target_buffer)${NC}"
    fi
    
    # 检查 wmem_max
    local wmem
    wmem=$(sysctl -n net.core.wmem_max 2>/dev/null)
    if [[ "$wmem" -ge "$target_buffer" ]]; then
        echo -e "UDP 发送缓冲区: ${GREEN}✅ 已优化 ($wmem)${NC}"
    else
        echo -e "UDP 发送缓冲区: ${YELLOW}⚠️  未达标 (当前: $wmem, 目标: $target_buffer)${NC}"
    fi
    
    check_bbr_status
}

# 配置带宽
configure_bandwidth() {
    echo ""
    log_info "配置服务器带宽限制..."
    echo -e "${BLUE}配置带宽有助于 Hysteria2 更好地进行拥塞控制 (Brutal算法)${NC}"
    echo -e "${YELLOW}请根据服务器实际带宽情况填写，填写 0 则不限制${NC}"
    
    echo -n -e "${BLUE}上传带宽 (Mbps) [默认: 100]: ${NC}"
    read -r up_mbps
    up_mbps=${up_mbps:-100}
    
    echo -n -e "${BLUE}下载带宽 (Mbps) [默认: 100]: ${NC}"
    read -r down_mbps
    down_mbps=${down_mbps:-100}
    
    if [[ "$up_mbps" =~ ^[0-9]+$ ]] && [[ "$down_mbps" =~ ^[0-9]+$ ]]; then
        # 检查配置文件是否存在
        local config_file="/etc/hysteria/config.yaml"
        if [[ -f "$config_file" ]]; then
            # 备份配置文件
            cp "$config_file" "${config_file}.bak"
            
            # 检查是否已存在带宽配置
            if grep -q "bandwidth:" "$config_file"; then
                # 使用 sed 替换已有的带宽配置块
                # 注意：这里假设带宽配置块格式标准，如果格式复杂可能需要更复杂的逻辑
                sed -i '/bandwidth:/,+2d' "$config_file"
            fi
            
            # 添加新的带宽配置
            # 找到 listen: 行，在后面添加带宽配置
            sed -i "/listen:/a bandwidth:\n  up: ${up_mbps} mbps\n  down: ${down_mbps} mbps" "$config_file"
            
            log_success "带宽配置已更新: 上传 ${up_mbps} Mbps, 下载 ${down_mbps} Mbps"
            
            # 询问是否重启服务
            echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
            read -r restart
            if [[ ! $restart =~ ^[Nn]$ ]]; then
                systemctl restart hysteria-server
                log_success "服务已重启"
            fi
        else
            log_error "未找到配置文件: $config_file"
        fi
    else
        log_error "带宽输入无效，请输入数字"
    fi
}

# 系统优化菜单
sys_optimization_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 系统性能优化 (BBR & Sysctl) ===${NC}"
        echo ""
        echo -e "${BLUE}说明: 针对 Hysteria 2 (QUIC/UDP) 优化内核参数，并开启 BBR${NC}"
        echo ""
        
        echo -e "${YELLOW}当前状态:${NC}"
        # 简单显示当前关键指标
        local current_rmem
        current_rmem=$(sysctl -n net.core.rmem_max 2>/dev/null)
        echo "UDP缓冲区: $((current_rmem / 1024 / 1024))MB" 
        echo -n "BBR状态: "
        local bbr
        bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [[ "$bbr" == *"bbr"* ]]; then
             echo -e "${GREEN}开启${NC}"
        else
             echo -e "${YELLOW}关闭${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}优化选项:${NC}"
        echo -e "${GREEN}1.${NC} 执行全面优化 (推荐)"
        echo -e "${GREEN}2.${NC} 配置带宽限制 (拥塞控制)"
        echo -e "${GREEN}3.${NC} 仅开启 BBR"
        echo -e "${GREEN}4.${NC} 仅优化 UDP 缓冲区"
        echo -e "${GREEN}5.${NC} 验证优化结果"
        echo -e "${RED}0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-5]: ${NC}"
        read -r choice
        
        case $choice in
            1)
                apply_sysctl_optimizations
                optimize_ulimit
                configure_bandwidth
                verify_optimization
                wait_for_user
                ;;
            2)
                configure_bandwidth
                wait_for_user
                ;;
            3)
                echo "正在开启 BBR..."
                cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
                sysctl --system >/dev/null 2>&1
                check_bbr_status
                wait_for_user
                ;;
            4)
                echo "正在优化 UDP 缓冲区..."
                # 检测系统内存
                local mem_total_kb
                mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "2000000")
                local mem_total_mb=$((mem_total_kb / 1024))
                
                local rmem_max=33554432
                local wmem_max=33554432
                local rmem_default=8388608
                local wmem_default=8388608
                
                if [[ "$mem_total_mb" -lt 1500 ]]; then
                    rmem_max=8388608
                    wmem_max=8388608
                    rmem_default=2097152
                    wmem_default=2097152
                    echo "内存 < 1.5GB，使用保守设置 (8MB)"
                else
                    echo "内存 >= 1.5GB，使用高性能设置 (32MB)"
                fi

                cat > /etc/sysctl.d/99-udp-buffer.conf <<EOF
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.core.rmem_default = $rmem_default
net.core.wmem_default = $wmem_default
EOF
                sysctl --system >/dev/null 2>&1
                verify_optimization
                wait_for_user
                ;;
            5)
                verify_optimization
                wait_for_user
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

# 导出函数
export -f sys_optimization_menu
