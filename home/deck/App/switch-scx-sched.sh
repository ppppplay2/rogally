#!/bin/bash
[ -t 1 ] || exec env -u LD_PRELOAD -u LD_LIBRARY_PATH -u STEAM_RUNTIME konsole -e bash "$0"
RAW=$(scxctl get)
CURR=$(echo "$RAW" | awk '{print $2}')

if [[ "$CURR" == "Cake" ]]; then
    sudo scxctl switch -s lavd
    TARGET="Lavd"
elif [[ "$CURR" == "Lavd" ]]; then
    sudo scxctl switch -s cake
    TARGET="Cake"
else
    sudo scxctl switch -s lavd
    TARGET="Cake"
fi
clear
echo "=================================================="
echo "           SCX 调度器切换成功"
echo "=================================================="
echo ""
echo "  当前调度器: $TARGET"
echo ""
echo "=================================================="
sleep 1
