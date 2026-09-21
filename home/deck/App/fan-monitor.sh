#!/bin/bash

if [ ! -t 1 ]; then
    exec env \
        -u LD_PRELOAD \
        -u LD_LIBRARY_PATH \
        -u STEAM_RUNTIME \
        /usr/bin/konsole -e /bin/bash -c "$0"
fi

clear
echo "=================================================="
echo "      ROG Ally 温度 / 风扇 实时监控"
echo "  风扇变化→新建行 | 无变化→1秒刷新当前行"
echo "      无日志 | 干净无报错 | Ctrl+C退出"
echo "=================================================="
echo ""

# 路径定义
FAN1_PATH="/sys/class/hwmon/hwmon6/fan1_input"
FAN2_PATH="/sys/class/hwmon/hwmon6/fan2_input"
TEMP_PATH="/sys/class/hwmon/hwmon4/temp1_input"

# 初始化变量
LAST_FAN1=""
LAST_FAN2=""
LAST_REFRESH=0
REFRESH_INTERVAL=1  # 无变化时1秒刷新一次当前行

while true; do
    TIME=$(date +"%H:%M:%S")
    NOW=$(date +%s)

    # 读取数据
    read -r FAN1 < "$FAN1_PATH" 2>/dev/null || FAN1=0
    read -r FAN2 < "$FAN2_PATH" 2>/dev/null || FAN2=0
    read -r TEMP < "$TEMP_PATH" 2>/dev/null || TEMP=0
    TEMP_C=$((TEMP / 1000))

    # ==============================================
    # 风扇转速变化：新建一行显示
    # ==============================================
    if [ "$FAN1" != "$LAST_FAN1" ] || [ "$FAN2" != "$LAST_FAN2" ]; then
        echo "[$TIME] 温度:$TEMP_C°C  风扇1:$FAN1  风扇2:$FAN2 RPM"
        LAST_FAN1="$FAN1"
        LAST_FAN2="$FAN2"
        LAST_REFRESH="$NOW"

    # ==============================================
    # 转速不变：1秒刷新一次当前行
    # ==============================================
    elif [ $((NOW - LAST_REFRESH)) -ge "$REFRESH_INTERVAL" ]; then
        printf "\r[当前状态] 温度:%d°C  风扇1:%d  风扇2:%d RPM (4秒自动刷新)" "$TEMP_C" "$FAN1" "$FAN2"
        LAST_REFRESH="$NOW"
    fi

    sleep 1
done
