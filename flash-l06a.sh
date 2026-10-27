#!/bin/bash
# L06A/LX06 小爱音箱 Linux 刷机脚本（依赖：libusb-compat 或 libusb-0.1）
# 用法: sudo ./flash-l06a.sh [固件文件路径.squashfs]
# 原理: Amlogic USB 烧录协议，无需打断 UBOOT 倒计时，直接 bulkcmd 下发 UBOOT 命令
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$DIR/update"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# system0 分区上限大小：40MB (0x2800000 = 41943040 字节)
MAX_PARTITION_SIZE=41943040

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { red "请用 sudo 运行此脚本"; exit 1; }
[ -x "$UPDATE" ] || { red "找不到 update 工具: $UPDATE"; exit 1; }

find_firmware() {
    # 1. 命令行参数优先
    if [ -n "${1:-}" ]; then
        if [ -f "$1" ]; then
            echo "$1"
            return 0
        else
            red "指定固件文件不存在: $1" >&2
            return 1
        fi
    fi

    # 2. firmware/ 目录下的 squashfs 镜像
    local match
    match=$(find "$DIR/firmware" -maxdepth 1 -type f -name "*.squashfs" 2>/dev/null | head -n 1)
    if [ -n "$match" ] && [ -f "$match" ]; then
        echo "$match"
        return 0
    fi

    # 3. 根目录下的 squashfs 镜像
    match=$(find "$DIR" -maxdepth 1 -type f -name "*.squashfs" 2>/dev/null | head -n 1)
    if [ -n "$match" ] && [ -f "$match" ]; then
        echo "$match"
        return 0
    fi

    # 4. 回退检查上级邻近 open-xiaoai 目录
    if [ -f "$DIR/../open-xiaoai/LX06_1.94.13_patched.squashfs" ]; then
        echo "$DIR/../open-xiaoai/LX06_1.94.13_patched.squashfs"
        return 0
    fi

    return 1
}

FIRMWARE=$(find_firmware "${1:-}") || {
    red "未找到可刷写的固件 (.squashfs)！"
    red "请将从 Open-XiaoAI 项目获取的补丁固件放入 firmware/ 目录，或者指定固件路径："
    red "  用法: sudo $0 /path/to/root_patched.squashfs"
    exit 1
}

actual_size=$(stat -c %s "$FIRMWARE")
if [ "$actual_size" -le 1048576 ]; then
    red "固件异常过小 ($actual_size 字节)，禁止刷写！"
    exit 1
fi
if [ "$actual_size" -gt "$MAX_PARTITION_SIZE" ]; then
    red "固件大小 ($actual_size 字节) 超过 system0 分区容量 ($MAX_PARTITION_SIZE 字节)，禁止刷写！"
    exit 1
fi

green "✓ 固件校验通过: $FIRMWARE ($actual_size 字节)"

yellow ""
yellow "============================================================"
yellow " 请现在【拔掉音箱电源，再重新插上】"
yellow " 脚本会自动捕获 USB 烧录窗口（最多等 120 秒）..."
yellow "============================================================"
yellow ""

found=0
deadline=$((SECONDS + 120))
while [ $SECONDS -lt $deadline ]; do
    out=$("$UPDATE" identify 2>&1)
    if echo "$out" | grep -qi "firmware version"; then
        green "✓ 已连接到设备: $(echo "$out" | grep -i 'firmware version')"
        found=1
        break
    fi
    sleep 0.2
done

if [ $found != 1 ]; then
    red "未检测到设备，排查："
    red "  1. 数据线必须插在主板 Micro USB 调试口（或 Type-C 口），且是数据线（非仅充电线）"
    red "  2. dmesg | tail 看是否有新的 USB 设备枚举"
    red "  3. lsusb 应出现 Amlogic/SEI 设备 (如 ID 1b8e:0cee)"
    red "  4. 部分板需按住 PLAY 键上电才进烧录模式"
    exit 1
fi

echo ""
yellow "[2/4] 设置 UBOOT 启动延时 15s（以后刷机不用再抢时间）..."
"$UPDATE" bulkcmd "setenv bootdelay 15" || { red "setenv bootdelay 失败"; exit 1; }

yellow "[3/4] 设置 boot0 为启动分区..."
"$UPDATE" bulkcmd "setenv boot_part boot0" || { red "setenv boot_part 失败"; exit 1; }
"$UPDATE" bulkcmd "saveenv" || { red "saveenv 失败"; exit 1; }
green "✓ 环境变量已保存 (boot_part=boot0, bootdelay=15)"

echo ""
yellow "[4/4] 刷写固件到 system0（约 1-2 分钟，切勿断电）..."
if "$UPDATE" partition system0 "$FIRMWARE"; then
    echo ""
    green "============================================================"
    green " ✅ 刷机成功！"
    green " 拔掉数据线和电源，重新插电。"
    green " 开机 1-2 分钟后可尝试 SSH 登录音箱。"
    green "============================================================"
else
    red "刷写失败。直接重跑本脚本重试（烧录窗口仍在，无需重拔电源）。"
    red "回滚原厂系统: sudo $UPDATE bulkcmd \"setenv boot_part boot1\" && sudo $UPDATE bulkcmd saveenv"
    exit 1
fi
