#!/bin/bash
# backup-all.sh — 通过 Amlogic USB 烧录口把全部分区备份到电脑
# 用法: sudo ./backup-all.sh [输出目录]
# 原理: 设备 U-Boot 的烧录窗口内，update mread 直接按分区名读闪存，
#       与设备系统是否联网、系统是否正常完全无关。
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$DIR/update"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
OUT="${1:-$DIR/backups/backup-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { red "请用 sudo 运行"; exit 1; }
[ -x "$UPDATE" ] || { red "找不到 $UPDATE"; exit 1; }

yellow ""
yellow "============================================================"
yellow " 先【拔掉音箱电源】，脚本就绪后重新插上"
yellow " 自动捕获 U-Boot 烧录窗口并备份全部分区（约 5-10 分钟）"
yellow "============================================================"
yellow ""

deadline=$((SECONDS + 180))
found=0
while [ $SECONDS -lt $deadline ]; do
    out=$("$UPDATE" identify 2>&1)
    if echo "$out" | grep -qi "firmware version"; then
        green "✓ 已连接: $(echo "$out" | grep -i 'firmware version' | head -1)"
        found=1
        break
    fi
    sleep 0.2
done
[ $found = 1 ] || { red "未捕获到烧录窗口，请检查 USB 线/接口后重试"; exit 1; }

# 分区表来自 U-Boot 日志（128MB NAND）: 名称:大小
PARTS="
bootloader:0x200000
tpl:0x800000
boot0:0x600000
boot1:0x600000
system0:0x2800000
system1:0x2800000
data:0x1400000
"

echo "$PARTS" | while IFS=: read -r name size; do
    [ -z "$name" ] && continue
    yellow "[备份] $name ($size) -> $OUT/$name.bin"
    if ! "$UPDATE" mread store "$name" normal "$size" "$OUT/$name.bin"; then
        red "[!] $name 备份失败（设备可能已离开烧录窗口，重跑本脚本）"
        exit 1
    fi
done

echo ""
green "============================================================"
green " 备份完成，输出目录: $OUT"
ls -la "$OUT"
green "============================================================"
yellow "校验: md5sum $OUT/*.bin > $OUT/MD5SUMS; 妥善另存一份"
