#!/bin/bash
# xiaoai-usb-tool.sh — 小爱音箱 L06A/LX06 纯 USB 烧录口交互工具
# 用法: sudo ./xiaoai-usb-tool.sh
#
# 覆盖全流程: 抓烧录窗口 → 修 UBOOT → 备份分区 → 刷机 → 切启动槽
# 依赖: 同目录 update 工具 (khadas aml-flash-tool) + libusb-0.1
# 注意: 不要手动在 UBOOT 里跑 update 500 1000 (此版固件 500 重试参数
#       不生效, 只挂 ~1.3s 就退出, 且会与 PC 端传输冲突)。抓窗一律用
#       本工具的 identify 循环。
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$DIR/update"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

WORKSPACE="$DIR"
MAX_PARTITION_SIZE=41943040

find_default_firmware() {
    local match
    match=$(find "$DIR/firmware" -maxdepth 1 -type f -name "*.squashfs" 2>/dev/null | head -n 1)
    if [ -n "$match" ] && [ -f "$match" ]; then
        echo "$match"
        return 0
    fi
    match=$(find "$DIR" -maxdepth 1 -type f -name "*.squashfs" 2>/dev/null | head -n 1)
    if [ -n "$match" ] && [ -f "$match" ]; then
        echo "$match"
        return 0
    fi
    if [ -f "$DIR/../open-xiaoai/LX06_1.94.13_patched.squashfs" ]; then
        echo "$DIR/../open-xiaoai/LX06_1.94.13_patched.squashfs"
        return 0
    fi
    return 1
}

# 分区表: 名称:十六进制大小（来自 UBOOT 日志, 128MB NAND）
PARTS="bootloader:0x200000 tpl:0x800000 boot0:0x600000 boot1:0x600000 system0:0x2800000 system1:0x2800000 data:0x1400000"

green()  { printf '\033[32m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { red "请用 sudo 运行"; exit 1; }
[ -x "$UPDATE" ] || { red "缺少 $UPDATE"; exit 1; }

CONNECTED=0

try_identify() {
    local out
    out=$("$UPDATE" identify 2>&1)
    if echo "$out" | grep -qi "firmware version"; then
        return 0
    fi
    return 1
}

# 抓烧录窗口: 已连接直接过; 否则提示拔插电源循环扫
ensure_conn() {
    if [ "$CONNECTED" = 1 ] && try_identify; then
        return 0
    fi
    yellow ""
    yellow "[*] 需要设备进入烧录窗口。请【拔掉音箱电源再重新插上】。"
    yellow "    若刚上电不久, 直接等待扫描即可 (最多 180 秒)..."
    local deadline=$((SECONDS + 180))
    while [ $SECONDS -lt $deadline ]; do
        if try_identify; then
            CONNECTED=1
            green "[*] 已连接设备 (烧录窗口内)"
            return 0
        fi
        sleep 0.2
    done
    red "[!] 未捕获窗口。检查: Micro USB 调试口 / 数据线 / lsusb 有无 Amlogic 设备"
    return 1
}

# 跑一条 PC 端 update 命令; 自动检测掉线
run_update() {
    local out
    out=$("$UPDATE" "$@" 2>&1)
    echo "$out"
    if echo "$out" | grep -qiE "can not find device|FAIL|ret=-5|ret=-110|failed"; then
        if echo "$out" | grep -qiE "can not find device|ret=-5|ret=-110"; then
            CONNECTED=0
            red "[!] 设备已离开烧录窗口 (可能已进系统)。重新选择操作并拔插电源。"
        fi
        return 1
    fi
    return 0
}

bulk() { run_update bulkcmd "$1"; }

menu() {
    echo ""
    echo "========== L06A/LX06 USB 工具 =========="
    echo " 连接状态: $([ "$CONNECTED" = 1 ] && echo 在线 || echo 离线)"
    echo "----------------------------------------"
    echo " 1) 连接设备 (抓烧录窗口)"
    echo " 2) 设置 UBOOT 等待时间 (bootdelay)"
    echo " 3) 查看 UBOOT 环境变量"
    echo " 4) 备份全部分区到电脑"
    echo " 5) 备份单个分区"
    echo " 6) 刷写 patched 到 system0 (设 boot_part=boot0)"
    echo " 7) 刷写自定义镜像到指定分区"
    echo " 8) 设置启动分区 (boot0 / boot1)"
    echo " 9) 执行自定义 UBOOT 命令"
    echo " 0) 退出"
    echo "========================================"
    printf "选择: "
}

do_bootdelay() {
    ensure_conn || return
    printf "输入 bootdelay 秒数 (默认 15): "
    read -r n
    n="${n:-15}"
    bulk "setenv bootdelay $n" && bulk "saveenv" && green "[✓] bootdelay=$n 已保存"
}

do_printenv() {
    ensure_conn || return
    bulk "printenv"
}

do_backup_all() {
    ensure_conn || return
    local outdir="$WORKSPACE/backups/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$outdir"
    green "[*] 备份到 $outdir"
    local name size
    echo "$PARTS" | tr ' ' '\n' | while IFS=: read -r name size; do
        [ -z "$name" ] && continue
        yellow "  -> $name ($size)"
        if ! run_update mread store "$name" normal "$size" "$outdir/$name.bin"; then
            red "[!] $name 失败, 已备份的分区在 $outdir"
            return 1
        fi
    done
    green "[✓] 完成"; ls -la "$outdir"
    yellow "    记得: md5sum $outdir/*.bin > $outdir/MD5SUMS 并另存一份"
}

do_backup_one() {
    ensure_conn || return
    local i=0 name size
    echo "$PARTS" | tr ' ' '\n' | while IFS=: read -r name size; do
        [ -n "$name" ] && echo "  $i) $name ($size)"
        i=$((i+1))
    done
    printf "输入分区名: "
    read -r p
    size=$(echo "$PARTS" | tr ' ' '\n' | grep "^$p:" | cut -d: -f2)
    [ -z "$size" ] && { red "未知分区: $p"; return; }
    mkdir -p "$WORKSPACE/backups"
    local out="$WORKSPACE/backups/${p}-$(date +%Y%m%d-%H%M%S).bin"
    run_update mread store "$p" normal "$size" "$out" && green "[✓] $out"
}

do_flash_patched() {
    local fw
    fw=$(find_default_firmware) || {
        yellow "未在 firmware/ 目录下找到 .squashfs 固件。"
        printf "请输入固件完整路径: "
        read -r fw
    }
    [ -f "$fw" ] || { red "固件不存在: $fw"; return; }
    local sz
    sz=$(stat -c %s "$fw")
    [ "$sz" -le 1048576 ] && { red "固件异常过小 ($sz 字节), 中止"; return; }
    [ "$sz" -gt "$MAX_PARTITION_SIZE" ] && { red "固件大小 $sz 超过 system0 分区上限 $MAX_PARTITION_SIZE, 中止"; return; }
    ensure_conn || return
    yellow "[*] 刷写 $fw 到 system0 (约 1-2 分钟, 勿断电)"
    if run_update partition system0 "$fw"; then
        green "[✓] 刷写成功"
        bulk "setenv boot_part boot0" && bulk "saveenv" \
            && green "[✓] 已设 boot_part=boot0, 重启生效" \
            || red "[!] 设启动分区失败, 手动: 菜单 8 选 boot0"
    else
        red "[!] 刷写失败。重试本菜单; 若反复失败想回滚: 菜单 8 选 boot1"
    fi
}

do_flash_custom() {
    ensure_conn || return
    printf "镜像文件绝对路径: "; read -r img
    [ -f "$img" ] || { red "文件不存在"; return; }
    printf "目标分区 (如 system0/system1/boot1): "; read -r part
    echo "$PARTS" | tr ' ' '\n' | grep -q "^$part:" || { red "未知分区: $part"; return; }
    yellow "[*] 刷写 $img -> $part (勿断电)"
    run_update partition "$part" "$img" && green "[✓] 完成"
}

do_boot_part() {
    ensure_conn || return
    printf "启动分区 [boot0/boot1] (当前: "; bulk "printenv boot_part" | tr -d '\r' | grep -o 'boot[01]'; printf "): "
    read -r p
    case "$p" in
        boot0|boot1) bulk "setenv boot_part $p" && bulk "saveenv" && green "[✓] 已设 $p, 重启生效" ;;
        *) red "只接受 boot0 或 boot1" ;;
    esac
}

do_bulk() {
    ensure_conn || return
    printf "UBOOT 命令: "; read -r cmd
    [ -n "$cmd" ] && bulk "$cmd"
}

while :; do
    menu
    read -r choice || break
    case "$choice" in
        1) if try_identify; then CONNECTED=1; green "[*] 在线"; else CONNECTED=0; ensure_conn; fi ;;
        2) do_bootdelay ;;
        3) do_printenv ;;
        4) do_backup_all ;;
        5) do_backup_one ;;
        6) do_flash_patched ;;
        7) do_flash_custom ;;
        8) do_boot_part ;;
        9) do_bulk ;;
        0) break ;;
        *) red "无效选择" ;;
    esac
done
green "[*] 退出"
