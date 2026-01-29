#!/bin/bash

# 脚本更新模块
# 用于检查和更新 s-hy2 管理脚本及其组件

# 引用公共函数库
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    # 简单的日志函数回退
    log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
    log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
    log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
fi

# 配置
REPO_OWNER="Xiaofei-Z"
REPO_NAME="s-hy2"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits/${BRANCH}"

# 脚本所在目录 (s-hy2/scripts)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录 (s-hy2)
PROJECT_DIR="$(dirname "$SCRIPTS_DIR")"

# 需要更新的文件列表
# 注意：sys-opt.sh 是新增加的
FILES_TO_UPDATE=(
    "hy2-manager.sh"
    "install.sh"
    "scripts/common.sh"
    "scripts/config.sh"
    "scripts/service.sh"
    "scripts/domain-test.sh"
    "scripts/node-info.sh"
    "scripts/outbound-manager.sh"
    "scripts/firewall-manager.sh"
    "scripts/post-deploy-check.sh"
    "scripts/sys-opt.sh"
    "scripts/update.sh"
    "scripts/input-validation.sh"
)

# 获取本地版本
get_local_version() {
    if [[ -f "$PROJECT_DIR/hy2-manager.sh" ]]; then
        grep -E "^# 版本:" "$PROJECT_DIR/hy2-manager.sh" | awk '{print $3}'
    else
        echo "0.0.0"
    fi
}

# 获取远程版本
get_remote_version() {
    # 尝试从远程 hy2-manager.sh 获取版本号
    local remote_content
    remote_content=$(curl -s --connect-timeout 5 "${BASE_URL}/hy2-manager.sh")
    
    if [[ -n "$remote_content" ]]; then
        echo "$remote_content" | grep -E "^# 版本:" | awk '{print $3}'
    else
        echo ""
    fi
}

# 版本比较函数
# 返回 0: version1 = version2
# 返回 1: version1 > version2
# 返回 2: version1 < version2
version_compare() {
    if [[ "$1" == "$2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($1) ver2=($2)
    
    # 填充空位
    for ((i=${#ver1[@]}; i<3; i++)); do ver1[i]=0; done
    for ((i=${#ver2[@]}; i<3; i++)); do ver2[i]=0; done
    
    for ((i=0; i<3; i++)); do
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    
    return 0
}

# 检查更新
check_update() {
    log_info "正在检查更新..."
    
    local local_ver=$(get_local_version)
    local remote_ver=$(get_remote_version)
    
    if [[ -z "$remote_ver" ]]; then
        log_warn "无法获取远程版本信息，请检查网络连接"
        return 1
    fi
    
    log_info "本地版本: $local_ver"
    log_info "最新版本: $remote_ver"
    
    version_compare "$local_ver" "$remote_ver"
    local result=$?
    
    if [[ $result -eq 2 ]]; then
        echo ""
        echo -e "\033[0;32m发现新版本: $remote_ver\033[0m"
        echo -n -e "\033[1;33m是否立即更新? [Y/n]: \033[0m"
        read -r confirm
        if [[ ! $confirm =~ ^[Nn]$ ]]; then
            perform_update "$remote_ver"
        else
            echo "已取消更新"
        fi
    else
        echo -e "\033[0;32m当前已是最新版本\033[0m"
        
        # 即使版本相同，也提供强制更新选项（修复文件损坏）
        echo ""
        echo -n -e "\033[1;33m是否强制重新下载所有脚本文件? (用于修复损坏) [y/N]: \033[0m"
        read -r force_update
        if [[ $force_update =~ ^[Yy]$ ]]; then
            perform_update "$remote_ver" "force"
        fi
    fi
}

# 执行更新
perform_update() {
    local version="$1"
    local force="${2:-}"
    
    echo ""
    log_info "开始更新脚本文件..."
    
    local success_count=0
    local fail_count=0
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    
    for file in "${FILES_TO_UPDATE[@]}"; do
        local filename=$(basename "$file")
        local target_path="$PROJECT_DIR/$file"
        local url="${BASE_URL}/${file}"
        
        # 确保目标目录存在
        mkdir -p "$(dirname "$target_path")"
        
        echo -n "正在更新 $file ... "
        
        if curl -s --connect-timeout 10 -o "$temp_dir/$filename" "$url"; then
            # 简单验证文件内容（检查是否包含 HTML 错误页）
            if grep -q "<!DOCTYPE html>" "$temp_dir/$filename"; then
                echo -e "\033[0;31m失败 (404 或网络错误)\033[0m"
                ((fail_count++))
            else
                # 移动文件并设置权限
                mv "$temp_dir/$filename" "$target_path"
                chmod +x "$target_path"
                echo -e "\033[0;32m成功\033[0m"
                ((success_count++))
            fi
        else
            echo -e "\033[0;31m下载失败\033[0m"
            ((fail_count++))
        fi
    done
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    echo ""
    if [[ $fail_count -eq 0 ]]; then
        log_success "更新完成! 所有文件已更新到版本 $version"
        echo -e "\033[1;33m请重启脚本以加载新功能\033[0m"
        exit 0
    else
        log_warn "更新完成，但有 $fail_count 个文件更新失败"
        log_info "成功更新: $success_count 个文件"
    fi
}

# 菜单入口
update_menu() {
    check_update
    
    echo ""
    read -p "按回车键返回..." -r
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    update_menu
fi
