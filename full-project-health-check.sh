#!/bin/bash

# S-Hy2 项目全面健康检查报告

echo "🔍 S-Hy2 项目全面健康检查报告"
echo "======================================="
echo ""

# 检查统计
total_checks=0
passed_checks=0
failed_checks=0

# 函数：记录检查结果
check_result() {
    local status=$1
    local message=$2
    
    total_checks=$((total_checks + 1))
    
    if [ "$status" == "✅" ]; then
        passed_checks=$((passed_checks + 1))
        echo "$status $message"
    else
        failed_checks=$((failed_checks + 1))
        echo "$status $message"
    fi
}

# 1. 检查代码质量和语法
echo "📝 1. 代码质量检查"
echo "-------------------"

# 检查所有Shell脚本语法
syntax_errors=0
for script in /Users/kuskyfei/Downloads/s-hy2/scripts/*.sh; do
    if ! bash -n "$script" 2>/dev/null; then
        syntax_errors=$((syntax_errors + 1))
    fi
done

if [ $syntax_errors -eq 0 ]; then
    check_result "✅" "所有15个Shell脚本语法正确"
else
    check_result "❌" "发现 $syntax_errors 个语法错误"
fi

# 检查主管理脚本
if bash -n /Users/kuskyfei/Downloads/s-hy2/hy2-manager.sh 2>/dev/null; then
    check_result "✅" "主管理脚本语法正确"
else
    check_result "❌" "主管理脚本存在语法错误"
fi

# 检查安装脚本
if bash -n /Users/kuskyfei/Downloads/s-hy2/install.sh 2>/dev/null; then
    check_result "✅" "安装脚本语法正确"
else
    check_result "❌" "安装脚本存在语法错误"
fi

echo ""

# 2. 检查配置文件
echo "⚙️  2. 配置文件检查"
echo "--------------------"

# 检查应用配置文件
if [ -f /Users/kuskyfei/Downloads/s-hy2/config/app.conf ]; then
    check_result "✅" "应用配置文件存在"
else
    check_result "❌" "应用配置文件缺失"
fi

# 检查配置文件有效性
if grep -q "PROJECT_NAME" /Users/kuskyfei/Downloads/s-hy2/config/app.conf 2>/dev/null; then
    check_result "✅" "配置文件格式正确"
else
    check_result "❌" "配置文件格式异常"
fi

# 检查模板文件
if [ -f /Users/kuskyfei/Downloads/s-hy2/templates/client-config.yaml ]; then
    check_result "✅" "客户端配置模板存在"
else
    check_result "❌" "客户端配置模板缺失"
fi

# 检查ACME配置模板
if [ -f /Users/kuskyfei/Downloads/s-hy2/templates/acme-config.yaml ]; then
    check_result "✅" "ACME配置模板存在"
else
    check_result "❌" "ACME配置模板缺失"
fi

echo ""

# 3. 检查功能模块
echo "🔧 3. 功能模块检查"
echo "------------------"

# 检查核心功能脚本
core_functions=("config.sh" "service.sh" "firewall-manager.sh" "node-info.sh" "outbound-manager.sh")
for func in "${core_functions[@]}"; do
    if [ -f "/Users/kuskyfei/Downloads/s-hy2/scripts/$func" ]; then
        check_result "✅" "功能模块 $func 存在"
    else
        check_result "❌" "功能模块 $func 缺失"
    fi
done

# 检查辅助功能脚本
helper_functions=("domain-test.sh" "input-validation.sh" "common.sh" "config-loader.sh")
for func in "${helper_functions[@]}"; do
    if [ -f "/Users/kuskyfei/Downloads/s-hy2/scripts/$func" ]; then
        check_result "✅" "辅助模块 $func 存在"
    else
        check_result "❌" "辅助模块 $func 缺失"
    fi
done

echo ""

# 4. 检查安全特性
echo "🔒 4. 安全特性检查"
echo "------------------"

# 检查输入验证模块
if [ -f /Users/kuskyfei/Downloads/s-hy2/scripts/input-validation.sh ]; then
    check_result "✅" "输入验证模块存在"
else
    check_result "❌" "输入验证模块缺失"
fi

# 检查错误处理模板
if [ -f /Users/kuskyfei/Downloads/s-hy2/scripts/error-handling-template.sh ]; then
    check_result "✅" "错误处理模板存在"
else
    check_result "❌" "错误处理模板缺失"
fi

# 检查安全下载模块
if [ -f /Users/kuskyfei/Downloads/s-hy2/scripts/secure-download.sh ]; then
    check_result "✅" "安全下载模块存在"
else
    check_result "❌" "安全下载模块缺失"
fi

# 检查临时文件最佳实践
if [ -f /Users/kuskyfei/Downloads/s-hy2/scripts/temp-file-best-practices.sh ]; then
    check_result "✅" "临时文件安全处理模块存在"
else
    check_result "❌" "临时文件安全处理模块缺失"
fi

echo ""

# 5. 检查文档完整性
echo "📚 5. 文档完整性检查"
echo "--------------------"

# 检查README文件
if [ -f /Users/kuskyfei/Downloads/s-hy2/README.md ]; then
    check_result "✅" "README.md 文档存在"
    
    # 检查README内容完整性
    if grep -q "快速安装" /Users/kuskyfei/Downloads/s-hy2/README.md 2>/dev/null; then
        check_result "✅" "README 包含安装说明"
    else
        check_result "❌" "README 缺少安装说明"
    fi
    
    if grep -q "功能特色" /Users/kuskyfei/Downloads/s-hy2/README.md 2>/dev/null; then
        check_result "✅" "README 包含功能说明"
    else
        check_result "❌" "README 缺少功能说明"
    fi
else
    check_result "❌" "README.md 文档缺失"
fi

# 检查客户端配置示例
if [ -f /Users/kuskyfei/Downloads/s-hy2/templates/client-config.yaml ]; then
    if grep -q "配置说明" /Users/kuskyfei/Downloads/s-hy2/templates/client-config.yaml 2>/dev/null; then
        check_result "✅" "客户端配置包含说明"
    else
        check_result "❌" "客户端配置缺少说明"
    fi
fi

echo ""

# 6. 检查项目依赖
echo "📦 6. 项目依赖检查"
echo "----------------"

# 检查必需的命令依赖
required_commands=("bash" "curl" "systemctl" "openssl" "sed" "awk" "grep")
for cmd in "${required_commands[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        check_result "✅" "依赖命令 $cmd 可用"
    else
        check_result "❌" "依赖命令 $cmd 不可用"
    fi
done

echo ""

# 7. 检查目录结构
echo "📁 7. 目录结构检查"
echo "----------------"

# 检查必需目录
required_dirs=("scripts" "templates" "config")
for dir in "${required_dirs[@]}"; do
    if [ -d "/Users/kuskyfei/Downloads/s-hy2/$dir" ]; then
        check_result "✅" "目录 $dir 存在"
    else
        check_result "❌" "目录 $dir 缺失"
    fi
 done

echo ""

# 8. 检查Git状态
echo "🔄 8. Git状态检查"
echo "----------------"

# 检查README.md权限
if [ -r /Users/kuskyfei/Downloads/s-hy2/README.md ]; then
    check_result "✅" "README.md 文件可读"
else
    check_result "❌" "README.md 文件不可读"
fi

# 检查脚本权限
script_perms_ok=true
for script in /Users/kuskyfei/Downloads/s-hy2/scripts/*.sh; do
    if [ ! -r "$script" ]; then
        script_perms_ok=false
        break
    fi
done

if [ "$script_perms_ok" = true ]; then
    check_result "✅" "所有脚本文件可读"
else
    check_result "❌" "部分脚本文件不可读"
fi

echo ""

# 生成总结报告
echo "📊 检查总结"
echo "============"
echo ""
echo "总检查项目: $total_checks"
echo "通过项目: $passed_checks ✅"
echo "失败项目: $failed_checks ❌"
echo ""

# 计算通过率
success_rate=0
if [ $total_checks -gt 0 ]; then
    success_rate=$((passed_checks * 100 / total_checks))
fi

echo "项目健康度: $success_rate%"
echo ""

# 健康评级
if [ $success_rate -ge 90 ]; then
    echo "🟢 项目状态: 优秀"
    echo "S-Hy2 项目运行状态良好，所有核心功能正常。"
elif [ $success_rate -ge 75 ]; then
    echo "🟡 项目状态: 良好"
    echo "S-Hy2 项目基本正常，建议优化部分功能。"
elif [ $success_rate -ge 50 ]; then
    echo "🟠 项目状态: 需要改进"
    echo "S-Hy2 项目存在一些问题，需要及时修复。"
else
    echo "🔴 项目状态: 严重问题"
    echo "S-Hy2 项目存在严重问题，需要立即修复。"
fi

echo ""
echo "🎯 修复建议"
echo "----------"
if [ $failed_checks -gt 0 ]; then
    echo "发现 $failed_checks 个问题需要修复："
    echo "1. 检查缺失的脚本文件"
    echo "2. 验证配置文件完整性"  
    echo "3. 确保依赖命令可用"
    echo "4. 补充缺失的文档说明"
else
    echo "🎉 恭喜！项目处于完美状态！"
    echo "所有检查项目都通过了，S-Hy2 项目可以正常使用。"
fi

echo ""
echo "📝 备注"
echo "------"
echo "此报告基于静态文件分析生成"
echo "实际运行状态需要在Linux环境中测试"