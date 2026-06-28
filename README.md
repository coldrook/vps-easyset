一键部署，自动化运维，节省时间
安全防护：Fail2ban 集成，自动封禁
日志管理：智能清理，减少维护成本
ssh 端口设置, 密钥 or 密码登录
蜜罐系统：模拟攻击行为，分析黑客模式

```sh
bash <(curl -sL https://raw.githubusercontent.com/coldrook/CyberSentry/refs/heads/main/install.sh)
```
### 服务管理

```bash
# 状态查看
systemctl status cowrie
systemctl status fail2ban
ufw status

# 日志查看
tail -f /opt/cowrie/var/log/cowrie/cowrie.log
journalctl -u cowrie -f
tail -f /var/log/fail2ban.log

# 服务控制
systemctl start|stop|restart cowrie
systemctl start|stop|restart fail2ban
```

### 安全建议

1. 安装完成后：
   - 保存显示的 SSH 端口号
   - 备份生成的 SSH 密钥（如果有）
   - 测试新配置前保留当前会话
2. 防火墙配置：
   - 确保必要端口已开放
   - 建议启用 UFW
   - 定期检查防火墙规则
3. 日常维护：
   - 定期检查系统日志
   - 监控蜜罐日志
   - 及时更新系统

### 卸载方法

```bash
# 停止服务
systemctl stop cowrie
systemctl disable cowrie

# 删除文件
rm -rf /opt/cowrie
rm /etc/systemd/system/cowrie.service

# 重载服务
systemctl daemon-reload
```


## 简易的logrotate安装脚本，对全局日志进行了限制

```sh
bash <(curl -sL https://raw.githubusercontent.com/coldrook/vps-easyset/refs/heads/main/log.sh)
```

## 一键修改系统自带的journal日志记录大小释放系统盘空间

支持系统：Ubuntu 18+，Debian 8+，centos 7+，Fedora，Almalinux 8.5+
1.自定义修改大小，单位为MB，一般500或者1000即可，有的系统日志默认给了5000甚至更多，不是做站啥的没必要
请注意，修改journal目录大小会影响系统日志的记录，因此，在修改journal目录大小之前如果需要之前的日志，建议先备份系统日志到本地
2.自定义修改设置系统日志保留日期时长，超过日期时长的日志将被清除
3.默认修改日志只记录warning等级(无法自定义)
4.以后日志的产生将受到日志文件大小，日志保留时间，日志保留等级的限制

```sh
curl -L https://raw.githubusercontent.com/spiritLHLS/one-click-installation-script/main/repair_scripts/resize_journal.sh -o resize_journal.sh && chmod +x resize_journal.sh && bash resize_journal.sh
```

## xanmod 内核与网络参数优化

   - 使用本仓库 `tcpx.sh`，先检测系统环境和版本，再调用 `manage_xanmod_kernel.sh` 安装 XanMod 内核，最后调用 `optimize_kernel_parameters.sh` 优化内核参数
   - XanMod MAIN 版本默认为 BBR3（替换了原来的 BBR），仅支持 Debian/Ubuntu x86_64
   - 查询当前 BBR：`cat /sys/module/tcp_bbr/version` 或 `modinfo tcp_bbr`
   - 安装新内核后通常需要重启，再用 `uname -r` 确认是否进入 XanMod 内核

```sh
wget -O tcpx.sh "https://raw.githubusercontent.com/coldrook/vps-easyset/refs/heads/main/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
```

## 简易的Docker Compose安装脚本，对全局日志进行了限制

```sh
bash <(curl -sL https://raw.githubusercontent.com/coldrook/vps-easyset/refs/heads/main/dc.sh)
```

### 卸载所有docker镜像和容器

```sh
docker rm -f $(docker ps -aq); docker rmi $(docker images -aq)
```
### 删除累积的docker日志

```sh
cd /var/lib/docker/containers/ && for container_id in */; do container_path="/var/lib/docker/containers/${container_id}"; log_file="${container_id%/}-json.log"; rm -rf "${container_path}${log_file}" && echo "已删除 ${container_path}${log_file}"; done
```

## 简易的dockge安装脚本，可自定义安装位置及端口

```sh
bash <(curl -sL https://raw.githubusercontent.com/coldrook/vps-easyset/refs/heads/main/dockge.sh)
```

## 简易的docker管理脚本，不依赖dockge

```sh
bash <(curl -sL https://raw.githubusercontent.com/coldrook/vps-easyset/refs/heads/main/easydocker.sh)
```
