#!/bin/bash
# uboot-cmd.sh — 通过 Amlogic USB 烧录协议在设备 U-Boot 里执行任意命令
#
# 用法:
#   交互模式:  sudo ./uboot-cmd.sh            （进入 uboot> 提示符，逐条执行）
#   批处理:    sudo ./uboot-cmd.sh "setenv bootdelay 15" "saveenv"
#
# 原理: 上电时 U-Boot 开启 USB 烧录窗口（日志里 InUsbBurn 阶段），
#       update 工具的 bulkcmd 经该协议直接在 U-Boot 内执行命令，
#       与串口倒计时无关，bootdelay=0 也拦不住。
#
# 注意: 窗口只在上电到内核启动前存在。玩久了设备进系统会断开，
#       脚本会提示重新拔插电源再抓。
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$DIR/update"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { red "请用 sudo 运行"; exit 1; }
[ -x "$UPDATE" ] || { red "找不到 $UPDATE"; exit 1; }

grab() {
    # 等待设备进入烧录窗口；已在窗口则立即返回
    local deadline=$((SECONDS + 120)) out
    yellow "[*] 等待设备进入烧录窗口（上电后 U-Boot 阶段，最多 120 秒）..."
    yellow "    若设备已启动进系统，请现在拔掉电源重新插上"
    while [ $SECONDS -lt $deadline ]; do
        out=$("$UPDATE" identify 2>&1)
        if echo "$out" | grep -qi "firmware version"; then
            green "[*] 已连接: $(echo "$out" | grep -i 'firmware version' | head -1)"
            return 0
        fi
        sleep 0.2
    done
    red "[!] 超时。检查: 数据线是否插在主板 Micro USB 调试口 / 是否数据线 / lsusb 有没有 Amlogic 设备"
    return 1
}

run_cmd() {
    local cmd="$1" out
    out=$("$UPDATE" bulkcmd "$cmd" 2>&1)
    echo "$out"
    if echo "$out" | grep -qi "failed\|error\|no device\|timeout"; then
        if echo "$out" | grep -qi "no device\|timeout"; then
            red "[!] 设备已离开烧录窗口（可能已进系统）。重新拔插电源后重试本条。"
            return 2
        fi
        return 1
    fi
    return 0
}

grab || exit 1

if [ $# -gt 0 ]; then
    # 批处理模式
    for cmd in "$@"; do
        yellow "uboot> $cmd"
        run_cmd "$cmd" || true
    done
    green "[*] 完成"
    exit 0
fi

# 交互模式
green "[*] 已进入 U-Boot 命令通道，输入 exit 或 quit 退出。示例:"
green "    setenv bootdelay 15        # 以后串口 15 秒内可手动打断"
green "    setenv boot_part boot0     # 指定启动分区"
green "    saveenv                    # 环境变量写盘（必须，否则断电失效）"
green "    printenv                   # 查看全部环境变量"
echo ""
while :; do
    printf '\033[36muboot>\033[0m '
    IFS= read -r cmd || break
    case "$cmd" in
        "" ) continue ;;
        exit|quit|q) break ;;
    esac
    run_cmd "$cmd"
done
green "[*] 退出"
