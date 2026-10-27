#!/usr/bin/env python3
"""
ttl-uboot.py — TTL 串口工具：透传 + 自动打断 autoboot 进 UBOOT

用法:
  venv/bin/python ttl-uboot.py [串口设备] [波特率]
  默认 /dev/ttyUSB0 @ 115200

行为:
  - 打开串口后每 0.5s 自动发一次回车，抓 U-Boot 倒计时窗口
  - 检测到 "=>" 提示符后自动停止发送，进入纯透传
  - Ctrl+] 退出
  - 全程日志写入 ttl-日志-<时间戳>.log

说明:
  patched 固件已把 bootdelay 设为 15s，上电后有 15 秒手动按回车的窗口；
  自动按回车是兜底（原厂 bootdelay=0 或saveenv未生效时也能进）。
"""
import os
import sys
import time
import threading
import datetime

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB0'
BAUD = int(sys.argv[2]) if len(sys.argv) > 2 else 115200

DIR = os.path.dirname(os.path.abspath(__file__))
LOGDIR = os.path.join(DIR, 'logs')
os.makedirs(LOGDIR, exist_ok=True)
LOGFILE = os.path.join(LOGDIR, 'ttl-%s.log' % datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))


def main():
    try:
        ser = serial.Serial(PORT, BAUD, timeout=0.1,
                            xonxoff=False, rtscts=False, dsrdtr=False)
    except serial.SerialException as e:
        print('[!] 打开串口失败: %s' % e, file=sys.stderr)
        sys.exit(1)

    stop_flood = threading.Event()

    def flood():
        # 自动按回车抓 autoboot；看到 "=>" 后停止
        n = 0
        while not stop_flood.is_set():
            try:
                ser.write(b'\r')
            except Exception:
                return
            n += 1
            if n == 1:
                print('\033[32m[*] 自动回车已开启，等待 U-Boot 提示符 "=>" ...\033[0m',
                      flush=True)
            time.sleep(0.5)

    def reader():
        buf = b''
        log = open(LOGFILE, 'ab', buffering=0)
        while True:
            try:
                data = ser.read(4096)
            except Exception:
                return
            if data:
                os.write(sys.stdout.fileno(), data)
                log.write(data)
                buf = (buf + data)[-300:]
                # U-Boot 提示符行尾
                if buf.rstrip().endswith(b'>'):
                    stop_flood.set()

    import termios
    import tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)

    print('\033[32m[*] %s @ %d — Ctrl+] 退出，日志: %s\033[0m' % (PORT, BAUD, LOGFILE),
          flush=True)
    threading.Thread(target=reader, daemon=True).start()
    threading.Thread(target=flood, daemon=True).start()

    try:
        tty.setraw(fd)
        while True:
            ch = os.read(fd, 1)
            if not ch:
                break
            if ch == b'\x1d':  # Ctrl+]
                break
            ser.write(ch)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        ser.close()
    print('\n[*] 已退出，日志保存在 %s' % LOGFILE)


if __name__ == '__main__':
    main()
