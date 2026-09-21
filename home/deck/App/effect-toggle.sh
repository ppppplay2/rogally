#!/bin/bash
[ -t 1 ] || exec env -u LD_PRELOAD -u LD_LIBRARY_PATH -u STEAM_RUNTIME konsole -e bash "$0"

find_module_id() {
    pw-cli list-objects Module 2>/dev/null | awk '
        /^id [0-9]+, type PipeWire:Interface:Module/ {
            id = $2
            gsub(/,/, "", id)
        }
        /module\.name = "libpipewire-module-filter-chain"/ {
            print id
            exit
        }
    '
}

CURR_ID=$(find_module_id)

if [ -n "$CURR_ID" ]; then
    pw-cli destroy "$CURR_ID" >/dev/null 2>&1
    TARGET="关闭"
    STATE="已关闭 (模块 ID: $CURR_ID 已销毁)"
else
    systemctl --user restart pipewire
    sleep 1
    NEW_ID=$(find_module_id)
    TARGET="开启"
    if [ -n "$NEW_ID" ]; then
        STATE="已开启 (模块 ID: $NEW_ID)"
    else
        STATE="重启失败，请检查配置文件"
    fi
fi

clear
echo "=================================================="
echo "           PipeWire 效果链切换成功"
echo "=================================================="
echo ""
echo "  当前状态: $STATE"
echo ""
echo "=================================================="
sleep 1
