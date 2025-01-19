#!/bin/bash

# 脚本名称: configure_logrotate_rsyslog.sh
# 描述: 配置 logrotate 来管理 rsyslog 日志，实现按周轮询，大小限制和保留历史版本
#       仅修改 /etc/logrotate.d/rsyslog 文件中 {} 内的内容

# 检查是否以 root 用户运行
if [[ $EUID -ne 0 ]]; then
  echo "错误: 请使用 sudo 或 root 用户运行此脚本。"
  exit 1
fi

# 安装必要的软件包
echo "安装 logrotate, cron 和 rsyslog..."
sudo apt update
sudo apt install -y logrotate cron rsyslog

# 获取 /etc/logrotate.d/rsyslog 文件内容
if [[ ! -f /etc/logrotate.d/rsyslog ]]; then
  echo "错误: /etc/logrotate.d/rsyslog 文件不存在。"
  exit 1
fi
OLD_CONFIG=$(sudo cat /etc/logrotate.d/rsyslog)

# 定义新的配置内容
NEW_CONFIG="
    weekly
    rotate 3
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
"

# 使用 sed 替换 {} 之间的内容
echo "修改 /etc/logrotate.d/rsyslog 文件..."
MODIFIED_CONFIG=$(echo "$OLD_CONFIG" | sed -E "s/\{[^{}]*\}/{\n$NEW_CONFIG\n}/")

# 将修改后的内容写回文件
echo "$MODIFIED_CONFIG" | sudo tee /etc/logrotate.d/rsyslog > /dev/null

# 检查 logrotate 服务状态
echo "检查 logrotate 服务状态..."
sudo systemctl status logrotate.service
sudo systemctl status logrotate.timer

echo "logrotate 配置完成。"
exit 0
