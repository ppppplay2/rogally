#!/bin/bash

if [[ -z "$TERM" ]];then
    export IN_TERM=1
    konsole --hold -e "$0"
    exit $?
fi

# ====================== 脚本配置区 ======================
# 默认兼容层路径（可直接修改这里修改默认值）
DEFAULT_PREFIX="/home/deck/prefix/default"
# Steam兼容层固定目录
STEAM_COMPAT_DIR="/home/deck/.steam/steam/steamapps/compatdata"
# ========================================================

# 清屏 + 欢迎提示
clear
echo "============================================="
echo "        Steam游戏兼容层软链接设置工具        "
echo "============================================="
echo ""

# 1. 提示输入游戏ID
read -p "请输入需要设置的游戏ID: " GAME_ID

# 判断是否输入了游戏ID（非空校验）
if [ -z "$GAME_ID" ]; then
    echo "错误：游戏ID不能为空！脚本退出"
    read -p "按回车键关闭终端..."
    exit 1
fi

# 2. 输入兼容层路径，提供默认值
read -p "请输入兼容层路径 [默认: $DEFAULT_PREFIX]: " CUSTOM_PREFIX
# 如果用户未输入，使用默认路径
PREFIX_PATH="${CUSTOM_PREFIX:-$DEFAULT_PREFIX}"

# 3. 拼接目标软链接完整路径
TARGET_PATH="${STEAM_COMPAT_DIR}/${GAME_ID}"

echo ""
echo "============================================="
echo "即将执行以下操作："
echo "游戏ID:        $GAME_ID"
echo "兼容层路径:    $PREFIX_PATH"
echo "目标链接路径:  $TARGET_PATH"
echo "============================================="
echo ""

# 4. 判断目标目录/软链接是否存在，存在则删除
if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
    echo "检测到已存在目录/软链接，正在删除..."
    rm -rf "$TARGET_PATH"
    if [ $? -eq 0 ]; then
        echo "✅ 旧目录/软链接删除成功"
    else
        echo "❌ 删除失败！脚本退出"
        read -p "按回车键关闭终端..."
        exit 1
    fi
else
    echo "未检测到旧目录/软链接，跳过删除步骤"
fi

echo ""

# 5. 创建软链接
echo "正在创建软链接..."
ln -s "$PREFIX_PATH" "$TARGET_PATH"

# 6. 校验软链接是否创建成功
if [ -L "$TARGET_PATH" ] && [ -d "$(readlink "$TARGET_PATH")" ]; then
    echo ""
    echo "============================================="
    echo "✅ 软链接创建成功！"
    echo "游戏 $GAME_ID 已绑定兼容层：$PREFIX_PATH"
    echo "============================================="
else
    echo ""
    echo "❌ 软链接创建失败！请检查路径是否正确"
fi

echo ""
read -p "操作完成，按回车键关闭终端..."
clear
exit 0
