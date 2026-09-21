#!/bin/bash

# 自动获取 root 权限（如果没有的话）
if [ $UID -ne 0 ]; then
    pkexec bash "$0" "$@"
    exit 0
fi

clear

DEFAULT_TDP=7

# ======================================================================

echo "====================================="
echo "      ROG Ally 省电模式"
echo "====================================="

echo -e "\n🔹 正在检查当前模式..."
CURRENT_PROFILE=$(asusctl profile get | head -n1 | awk '{print $NF}')

if [[ "$CURRENT_PROFILE" == "LowPower" ]]; then
    echo "ℹ️ 当前已是 LowPower 模式，无需切换"
else
    echo "✅ 当前不是 LowPower 模式，正在切换..."
    asusctl profile set LowPower
    sleep 2
fi

# 下面这 3 个输入 100% 会弹出提示！
read -p "请输入 TDP (W)，默认 $DEFAULT_TDP：" USER_TDP
read -p "是否写入风扇曲线？(y/N) 默认不写入：" SET_FAN

TARGET_TDP=${USER_TDP:-$DEFAULT_TDP}

PL1=$TARGET_TDP
PL2=$TARGET_TDP
PL3=$TARGET_TDP

[ $PL2 -lt 15 ] && PL2=15
[ $PL3 -lt 15 ] && PL3=15

echo -e "\n正在设置："
echo "✅ PL1 (ppt_pl1_spl)：${PL1}W"
echo "✅ PL2 (ppt_pl2_sppt)：${PL2}W"
echo "✅ PL3 (ppt_pl3_fppt)：${PL3}W"

BASE="/sys/class/firmware-attributes/asus-armoury/attributes"
if [ -d "$BASE/ppt_pl1_spl" ]; then
    echo "$PL1" > "$BASE/ppt_pl1_spl/current_value"
    echo "$PL2" > "$BASE/ppt_pl2_sppt/current_value"
    echo "$PL3" > "$BASE/ppt_pl3_fppt/current_value"
fi

if [[ "$SET_FAN" == "y" || "$SET_FAN" == "Y" ]]; then
    echo -e "\n🔧 正在写入风扇曲线..."
    HWMON="/sys/devices/platform/asus-nb-wmi/hwmon/hwmon7"

    echo 30 > "$HWMON/pwm1_auto_point1_temp"
    echo 0  > "$HWMON/pwm1_auto_point1_pwm"
    echo 30 > "$HWMON/pwm2_auto_point2_temp"
    echo 0  > "$HWMON/pwm2_auto_point1_pwm"

    echo 40 > "$HWMON/pwm1_auto_point2_temp"
    echo 0  > "$HWMON/pwm1_auto_point2_pwm"
    echo 40 > "$HWMON/pwm2_auto_point2_temp"
    echo 0  > "$HWMON/pwm2_auto_point2_pwm"

    echo 50 > "$HWMON/pwm1_auto_point3_temp"
    echo 0  > "$HWMON/pwm1_auto_point3_pwm"
    echo 50 > "$HWMON/pwm2_auto_point3_temp"
    echo 0  > "$HWMON/pwm2_auto_point3_pwm"

    echo 64 > "$HWMON/pwm1_auto_point4_temp"
    echo 30 > "$HWMON/pwm1_auto_point4_pwm"
    echo 64 > "$HWMON/pwm2_auto_point4_temp"
    echo 30 > "$HWMON/pwm2_auto_point4_pwm"

    echo 70 > "$HWMON/pwm1_auto_point5_temp"
    echo 30 > "$HWMON/pwm1_auto_point5_pwm"
    echo 70 > "$HWMON/pwm2_auto_point5_temp"
    echo 30 > "$HWMON/pwm2_auto_point5_pwm"

    echo 80 > "$HWMON/pwm1_auto_point6_temp"
    echo 40 > "$HWMON/pwm1_auto_point6_pwm"
    echo 80 > "$HWMON/pwm2_auto_point6_temp"
    echo 40 > "$HWMON/pwm2_auto_point6_pwm"

    echo 90 > "$HWMON/pwm1_auto_point7_temp"
    echo 40 > "$HWMON/pwm1_auto_point7_pwm"
    echo 90 > "$HWMON/pwm2_auto_point7_temp"
    echo 40 > "$HWMON/pwm2_auto_point7_pwm"

    echo 99 > "$HWMON/pwm1_auto_point8_temp"
    echo 40 > "$HWMON/pwm1_auto_point8_pwm"
    echo 99 > "$HWMON/pwm2_auto_point8_temp"
    echo 40 > "$HWMON/pwm2_auto_point8_pwm"
else
    echo -e "\nℹ️ 跳过风扇曲线设置"
fi

echo -e "\033[32m✅ 全部设置完成！\033[0m"
echo -e "\n按 任意键 退出窗口..."
read -n 1 -s -r
