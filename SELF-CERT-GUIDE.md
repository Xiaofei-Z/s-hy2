# S-Hy2 自签名证书配置完整指南

## 🎯 适用场景

✅ **适合使用自签名证书的情况**:
- 没有真实域名
- 服务器使用IP地址访问
- 测试环境或个人使用
- 不需要正式SSL证书

---

## 🛠️ 快速修复（推荐方案）

### 步骤1: 上传修复工具到服务器

```bash
# 从本地上传
scp self-cert-fix.sh root@your-server-ip:/root/

# SSH登录服务器
ssh root@your-server-ip
```

### 步骤2: 运行修复工具

```bash
# 添加执行权限
chmod +x /root/self-cert-fix.sh

# 运行修复工具
sudo /root/self-cert-fix.sh
```

### 步骤3: 按照提示配置

系统会自动：
- ✅ 停止当前服务
- ✅ 收集服务器信息
- ✅ 生成自签名证书
- ✅ 创建配置文件
- ✅ 启动服务

**需要手动输入的参数**:
- 监听端口（默认443，直接回车）
- 伪装域名（默认www.microsoft.com，直接回车）
- 带宽限制（默认100MB/s，直接回车）

---

## 📱 客户端配置

### 选项1: 使用 Hysteria2 原生链接

**步骤**:
1. 服务器修复后会显示原生的 Hysteria2 链接
2. 复制链接到支持 Hysteria2 的客户端
3. 重要：启用"跳过证书验证"或"不安全连接"

**示例链接格式**:
```
hysteria2://password@server-ip:443?insecure=1&obfs=salamander&obfs-password=xxx&sni=www.microsoft.com#S-Hy2-Node
```

---

### 选项2: 使用 Clash 订阅链接

**步骤**:
1. 修复工具会自动生成 Clash 订阅链接
2. 复制订阅链接到 Clash 客户端
3. 客户端中启用"跳过证书验证"

**Clash 配置示例**:
```yaml
proxies:
  - name: "S-Hy2-Server"
    type: hysteria2
    server: your-server-ip
    port: 443
    password: your-password
    obfs: salamander
    obfs-password: your-obfs-password
    sni: www.microsoft.com
    skip-cert-verify: true  # 关键配置！
    alpn:
      - h3
```

---

### 选项3: 手动配置

#### Windows 客户端（clash-verge）
```yaml
listen: 127.0.0.1:7890
allow-lan: true
mode: rule
log-level: info
proxies:
  - name: "S-Hy2"
    type: hysteria2
    server: 你的服务器IP
    port: 443
    password: 你的认证密码
    obfs: salamander
    obfs-password: 你的混淆密码
    sni: www.microsoft.com
    skip-cert-verify: true  # 必需项！
proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "S-Hy2"
rules:
  - MATCH,PROXY
```

#### Android 客户端（clash-for-android）
1. 添加节点
2. 类型选择：HYSTERIA2
3. 填入服务器IP、端口、密码
4. 启用："跳过证书验证"
5. SNI填写：www.microsoft.com

#### iOS 客户端（shadowrocket）
1. 添加节点
2. 选择类型：Hysteria2
3. 填入配置信息
4. 开启SNI: www.microsoft.com
5. 允许不安全连接

---

## 🔧 服务管理

### 启动服务
```bash
sudo systemctl start hysteria-server.service
```

### 停止服务
```bash
sudo systemctl stop hysteria-server.service
```

### 重启服务
```bash
sudo systemctl restart hysteria-server.service
```

### 查看状态
```bash
sudo systemctl status hysteria-server.service
```

### 查看日志
```bash
sudo journalctl -u hysteria-server.service -f
```

### 查看最近错误
```bash
sudo journalctl -u hysteria-server.service --no-pager -n 50
```

---

## 🔍 故障排除

### 问题1: 服务启动失败

**检查**:
```bash
# 查看服务状态
sudo systemctl status hysteria-server.service

# 查看详细错误
sudo journalctl -u hysteria-server.service -n 20

# 检查配置文件
cat /etc/hysteria/config.yaml

# 检查证书文件
ls -la /etc/hysteria/certs/
```

**可能原因**:
- 端口被占用
- 证书文件权限错误
- 配置文件格式错误

**解决方案**:
```bash
# 检查端口占用
sudo netstat -tuln | grep :443

# 修复证书权限
sudo chmod 600 /etc/hysteria/certs/server.key
sudo chmod 644 /etc/hysteria/certs/server.crt

# 重新启动服务
sudo systemctl restart hysteria-server.service
```

---

### 问题2: 客户端无法连接

**检查清单**:
- [ ] 服务器IP地址正确
- [ ] 端口号正确
- [ ] 防火墙已开放端口
- [ ] 客户端启用了"跳过证书验证"

**防火墙配置**:
```bash
# Ubuntu/Debian
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw reload

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=443/udp
sudo firewall-cmd --reload
```

---

### 问题3: Clash订阅链接404错误

**检查**:
```bash
# 检查HTTP服务器是否运行
sudo systemctl status nginx

# 检查订阅目录
ls -la /var/www/html/sub/

# 检查nginx配置
sudo nginx -t
```

**解决方案**:
```bash
# 启动HTTP服务器
sudo systemctl start nginx
sudo systemctl enable nginx

# 重新生成订阅链接
sudo s-hy2
# 选择 8. 节点信息
```

---

### 问题4: 证书验证错误

**客户端操作**:

**Clash**: 在配置中添加 `skip-cert-verify: true`

**Hysteria2**: 启用 "不安全连接" 选项

**其他客户端**: 寻找类似 "跳过证书验证"、"允许不安全连接" 的选项

---

## 📋 重要信息保存位置

修复工具会保存连接信息到：

```bash
/etc/hysteria/node-info.txt
```

查看连接信息：
```bash
cat /etc/hysteria/node-info.txt
```

---

## 🔒 安全建议

### 1. 定期更换密码
```bash
# 使用修复工具重新配置
sudo /root/self-cert-fix.sh
```

### 2. 修改认证密码
```bash
# 编辑配置文件
sudo nano /etc/hysteria/config.yaml

# 修改密码后重启服务
sudo systemctl restart hysteria-server.service
```

### 3. 限制访问（可选）
```bash
# 使用iptables限制只允许特定IP访问
sudo iptables -A INPUT -p tcp --dport 443 -s 特定IP -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j DROP
```

---

## 📊 性能优化

### 1. 调整带宽限制
```bash
# 编辑配置文件
sudo nano /etc/hysteria/config.yaml

# 修改带宽配置
bandwidth:
  up: 1000 mbps      # 上行带宽
  down: 1000 mbps    # 下行带宽

# 重启服务
sudo systemctl restart hysteria-server.service
```

### 2. 启用快速打开
```bash
# 确保配置中有以下设置
fastOpen:
  udp: true
```

---

## 🎯 常见使用场景

### 场景1: 个人代理
- ✅ 使用自签名证书
- ✅ IP地址访问
- ✅ Clash/Hysteria2客户端
- ⚠️ 客户端需要信任证书

### 场景2: 团队共享
- ✅ 共享连接信息
- ✅ 每个人配置客户端
- ⚠️ 定期更换密码

### 场景3: 多设备连接
- ✅ 同一个账号多设备
- ✅ Clash订阅链接方便分发
- ⚠️ 监控带宽使用

---

## 🚀 下一步

### 完成配置后：

1. **测试连接**
   ```bash
   # 在服务器上测试
   curl https://www.microsoft.com
   ```

2. **客户端配置**
   - 导入Hysteria2链接或Clash订阅
   - 启用"跳过证书验证"
   - 测试连接是否正常

3. **配置规则**
   - 设置分流规则
   - 添加代理规则
   - 配置DNS

4. **监控服务**
   ```bash
   # 实时查看日志
   sudo journalctl -u hysteria-server.service -f
   
   # 查看服务状态
   sudo systemctl status hysteria-server.service
   ```

---

## 📞 获取帮助

### 诊断工具
```bash
# 运行诊断
sudo /root/diagnose-service.sh
```

### 查看文档
```bash
# 查看项目README
cat /root/s-hy2/README.md

# 查看连接信息
cat /etc/hysteria/node-info.txt
```

### 获取支持
- GitHub Issues: https://github.com/Xiaofei-Z/s-hy2/issues
- 查看日志: `journalctl -u hysteria-server.service -n 100`

---

## ✨ 配置成功标志

如果看到以下信息，说明配置成功：

1. ✅ `systemctl status` 显示服务状态为 `active (running)`
2. ✅ 客户端能成功连接
3. ✅ Clash订阅链接能正常下载
4. ✅ 代理流量正常通过

---

**祝贺！你的 S-Hy2 服务现在已经使用自签名证书正常运行了！** 🎉