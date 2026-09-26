#!/bin/bash
# fan-set.sh 数字选择，不重启asusd、不切换当前运行模式
declare -A name_arr
declare -A curve_arr

# 预设：1=LowPower  2=Balanced  3=Performance
name_arr[1]="LowPower"
curve_arr[1]="45:30,64:30,66:30,69:30,79:30,85:30,92:30,99:30"

name_arr[2]="Balanced"
curve_arr[2]="54:30,59:40,64:55,69:75,74:95,79:122,84:122,94:122"

name_arr[3]="Performance"
curve_arr[3]="60:70,64:90,68:110,72:125,76:138,79:145,82:150,90:150"

echo "====风扇曲线快捷配置===="
echo "1 → LowPower"
echo "2 → Balanced"
echo "3 → Performance"
read -p "输入序号(1/2/3)：" num

if [[ -z "${name_arr[$num]}" ]]; then
    echo "错误：无效序号"
    exit 1
fi

PROFILE="${name_arr[$num]}"
DATA="${curve_arr[$num]}"

echo "正在写入【$PROFILE】曲线：$DATA"
asusctl fan-curve --mod-profile "$PROFILE" --fan cpu --data "$DATA"
asusctl fan-curve --mod-profile "$PROFILE" --fan gpu --data "$DATA"
asusctl fan-curve --mod-profile "$PROFILE" --enable-fan-curves true

echo -e "\n✅ 配置写入完毕，未重启服务、不改动当前运行模式"
