#!/bin/bash

if [ "$1" != "new_terminal" ]; then
    konsole -e bash -c "$0 new_terminal; exec bash"
    exit 0
fi
clear

# 自动获取 root 权限（如果没有的话）
if [ $UID -ne 0 ]; then
    pkexec bash "$0" "$@"
    exit 0
fi


echo "======================= SMB 服务控制 ======================="
echo " 1. 启动 SMB"
echo " 2. 停止 SMB"
echo " 3. 重启 SMB"
echo " 4. 查看 SMB 状态"
echo " 5. 重载配置 (修改 smb.conf 后用)"
echo " 6. 退出"
echo "============================================================"
read -p "请输入选项 [1-6]: " opt

case $opt in
    1)
        sudo systemctl start smb
        echo "✅ SMB 已启动"
        ;;
    2)
        sudo systemctl stop smb
        echo "🛑 SMB 已停止"
        ;;
    3)
        sudo systemctl restart smb
        echo "🔁 SMB 已重启"
        ;;
    4)
        systemctl status smb --no-pager
        ;;
    5)
        testparm -s
        sudo systemctl reload smb
        echo "🔄 配置已重载"
        ;;
    6)
        exit 0
        ;;
    *)
        echo "❌ 无效选项"
        ;;
esac
