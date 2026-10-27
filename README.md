# 小爱音箱 Linux 原生 USB 刷机与底层工具套件

本项目是专为**小米 Sound 高保真音箱 (L06A)**、**小爱音箱 Pro (LX06)** 以及 **Xiaomi 智能音箱 Pro (OH2P)** 打造的**纯 Linux 原生 USB 刷机、闪存备份、双槽切换与 U-Boot 底层交互工具套件**。

[English Documentation (README_EN.md)](README_EN.md)

---

## 声明与项目边界 (Disclaimer & Attribution)

> [!IMPORTANT]
> - **纯工具定位**：本项目专注于提供 **Linux 平台原生、免虚拟机、纯命令行** 的底层 USB 烧录通信、分区全量提取与 U-Boot 交互通道。
> - **不内置第三方固件与系统补丁**：根据开源规范与权利归属原则，本项目**不分发**任何第三方修改版固件镜像（`*.squashfs`）或上游系统 Patch 源码。
> - **致敬上游项目**：
>   - 固件修改逻辑、SSH 解锁方案、防 OTA 升级机制及 AI 扩展能力均归属于开源项目 **[Open-XiaoAI (idootop/open-xiaoai)](https://github.com/idootop/open-xiaoai)**（作者 [@idootop](https://github.com/idootop)）。
>   - 底层 Linux USB 烧录二进制工具基于晶晨开源套件 **[@khadas/utils (aml-flash-tool)](https://github.com/khadas/utils/tree/master/aml-flash-tool)**。

---

## 目录
- [一、支持机型与底层硬件架构](#一支持机型与底层硬件架构)
- [二、核心特性与对比](#二核心特性与对比)
- [三、获取固件 (来自 Open-XiaoAI)](#三获取固件-来自-open-xiaoai)
- [四、环境准备与依赖安装](#四环境准备与依赖安装)
- [五、硬件连接与接线说明](#五硬件连接与接线说明)
- [六、详细使用指南](#六详细使用指南)
  - [1. 刷机前推荐：全部分区全量备份 (backup-all.sh)](#1-刷机前推荐全部分区全量备份-backup-allsh)
  - [2. 一键全自动刷机 (flash-l06a.sh)](#2-一键全自动刷机-flash-l06ash)
  - [3. 交互式多功能工具箱 (xiaoai-usb-tool.sh)](#3-交互式多功能工具箱-xiaoai-usb-toolsh)
  - [4. U-Boot 命令直通终端 (uboot-cmd.sh)](#4-u-boot-命令直通终端-uboot-cmdsh)
  - [5. TTL 串口自动打断工具 (ttl-uboot.py)](#5-ttl-串口自动打断工具-ttl-ubootpy)
- [七、双系统槽位机制与一秒防砖回滚](#七双系统槽位机制与一秒防砖回滚)
- [八、刷机后连接与验证](#八刷机后连接与验证)
- [九、常见问题排查 (FAQ)](#九常见问题排查-faq)

---

## 一、支持机型与底层硬件架构

| 设备型号 | 产品名称 | 主控芯片 (SoC) | 闪存介质与容量 | 内部接口 |
| :--- | :--- | :--- | :--- | :--- |
| **L06A** | 小米 Sound 高保真智能音箱 | Amlogic A113X (4核 Cortex-A53) | 128MB SLC NAND | 主板 Micro USB 调试口 |
| **LX06** | 小爱音箱 Pro | Amlogic A113X (4核 Cortex-A53) | 128MB SLC NAND | 主板 Micro USB 调试口 |
| **OH2P** | Xiaomi 智能音箱 Pro | Amlogic A113X (4核 Cortex-A53) | 128MB SLC NAND | Type-C 调试口 / 内部口 |

### 闪存分区结构 (128MB NAND)
芯片硬件底层采用严谨的 A/B 双系统槽位冗余设计：
```text
[bootloader: 2MB] -> [tpl: 8MB] -> [boot0: 6MB] -> [boot1: 6MB] -> [system0: 40MB] -> [system1: 40MB] -> [data: 20MB]
```

---

## 二、核心特性与对比

| 特性维度 | 原版 Open-XiaoAI 官方指南 | 本工具套件 (xiaoai-flash-linux) |
| :--- | :--- | :--- |
| **操作系统支持** | 主要针对 Windows（提供批处理脚本与驱动安装器）及 macOS | **纯原生 Linux 环境**，支持各类主流发行版 |
| **USB 驱动依赖** | 需要安装闭源 Windows 晶晨专用驱动 | **免驱动**，直通标准 Linux `libusb` 内核接口 |
| **烧录窗口捕获** | 手动快速抢按命令，容易因时机不准超时错过 | **200ms 高频循环自动握手**，插电即 100% 毫秒级捕获 |
| **安全回滚设计** | 仅写入 `system0`，但缺乏现成脚本工具快速切换 | **双槽一键切换**，原厂系统保留在 `system1`，一秒无损回滚 |
| **全量闪存备份** | 官方未提供自动化提取脚本 | **一键读取导出 NAND 全部 7 个分区** 二进制镜像 |
| **终端命令通道** | 需焊接 TTL 飞线才能执行 U-Boot 命令 | **USB bulkcmd 直通**，无需飞线即可免拆调试 U-Boot |

---

## 三、获取固件 (来自 Open-XiaoAI)

在开始刷机之前，请准备好适用于你音箱型号的 `.squashfs` 固件镜像。

### 获取渠道：
1. **直接下载预编译镜像**：
   前往 [Open-XiaoAI Releases](https://github.com/idootop/open-xiaoai/releases) 页面，下载对应机型的发布包（例如 `LX06_1.94.13_patched.squashfs` 或 `root_patched.squashfs`）。
2. **源码自行构建**：
   参考 Open-XiaoAI 的 [packages/client-patch 文档](https://github.com/idootop/open-xiaoai/tree/main/packages/client-patch) 制作固件。上游补丁核心包括：
   - `01-ssh.patch`：植入 Dropbear SSH 服务；
   - `02-login.patch`：预设 root 密码（官方默认通常为 `open-xiaoai`）；
   - `03-ota.patch`：拦截 `/bin/ota`、`/bin/flash.sh` 与配网脚本中的静默升级逻辑；
   - `04-start.patch`：设置客户端自启。

### 固件存放：
下载或编译出的镜像文件，可直接放置在本项目根目录下的 `firmware/` 文件夹中（脚本会自动优先在此目录查找 `.squashfs` 文件），亦可在执行脚本时直接传入绝对路径。

---

## 四、环境准备与依赖安装

### 1. 安装 libusb 运行时兼容库 (必须)
底层 `update` 原生二进制烧录工具依赖 `libusb-0.1` 动态链接库。

- **Arch Linux / Manjaro**：
  ```bash
  sudo pacman -S libusb-compat
  ```
- **Ubuntu / Debian**：
  ```bash
  sudo apt update
  sudo apt install -y libusb-0.1-4
  # 若提示包名不存在，可尝试：sudo apt install -y libusb-compat-0.1-4
  ```
- **Fedora / RHEL / CentOS**：
  ```bash
  sudo dnf install -y libusb-compat-0.1
  ```
- **openSUSE**：
  ```bash
  sudo zypper in libusb-0_1-4
  ```

> [!NOTE]
> 本工具包已在 `lib/` 目录下内置了针对 x86_64 Linux 编译的 `libusb-0.1.so.4`，各脚本已预设 `LD_LIBRARY_PATH` 自动检索该目录。

### 2. 配置 udev 规则 (可选，免 sudo 执行)
默认情况下，访问未注册的底层 USB 块设备需要 root 权限。若希望普通用户直接运行 `update`，可安装本工具提供的规则：
```bash
sudo cp udev/99-amlogic.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 3. 串口交互依赖 (仅在使用 `ttl-uboot.py` 时需要)
```bash
pip install pyserial
# 或通过发行版包管理器安装：sudo pacman -S python-pyserial / sudo apt install python3-serial
```

---

## 五、硬件连接与接线说明

1. **线缆要求**：
   - 准备一根品质良好的 **Micro USB 数据线**（或部分新款机型的 Type-C 数据线）；
   - **重要红线**：严禁使用仅具备充电功能的两芯线！必须确保数据线具备完整的 D+ / D- 数据通信能力。
2. **连接调试端口**：
   - **小米 Sound (L06A) / 小爱音箱 Pro (LX06)**：
     揭开音箱底部的防滑胶垫，拧下固定螺丝拆卸底壳。在主板边缘左上角可看到 **Micro USB 调试接口**。将数据线一头插入该接口，另一头插入 Linux 电脑。
   - **Xiaomi 智能音箱 Pro (OH2P)**：
     新款若机身外置 Type-C 调试口，直接连线即可。
3. **独立电源供电**：
   - 音箱上电时功耗较大，**USB 接口仅传输数据，严禁仅依靠 USB 供电**。音箱原装 DC 适配器必须随时待命供电。

---

## 六、详细使用指南

### 1. 刷机前推荐：全部分区全量备份 (`backup-all.sh`)
在对 NAND 进行任何写入之前，**强烈建议先行完整备份出厂原始固件**。

```bash
# 默认备份到 backups/backup-<时间戳>/ 目录
sudo ./backup-all.sh

# 或指定自定义保存路径：
sudo ./backup-all.sh /home/user/xiaoai_backup
```

**运行逻辑**：
1. 终端提示拔插音箱电源；
2. 捕获到 U-Boot 烧录窗口后，利用 Amlogic 底层 `update mread` 指令，直接按十六进制大小依次导出物理分区：
   - `bootloader.bin` (2MB)
   - `tpl.bin` (8MB)
   - `boot0.bin` (6MB) / `boot1.bin` (6MB)
   - `system0.bin` (40MB) / `system1.bin` (40MB)
   - `data.bin` (20MB)
3. 备份完成后，自动计算并在终端列出备份文件。

---

### 2. 一键全自动刷机 (`flash-l06a.sh`)
最简便、经过实机高频测试的自动化刷机入口。

```bash
# 自动查找 firmware/ 目录下的 .squashfs 镜像
sudo ./flash-l06a.sh

# 或在命令行后直接附加自定义固件路径：
sudo ./flash-l06a.sh /path/to/my_firmware.squashfs
```

**自动化流程详解**：
1. **固件安全检查**：检测文件存在性，并确保固件容量不超过 40MB（`system0` 分区硬件上限）；
2. **等待上电握手**：
   ```text
   ============================================================
    请现在【拔掉音箱电源，再重新插上】
    脚本会自动捕获 USB 烧录窗口（最多等 120 秒）...
   ============================================================
   ```
3. **窗口捕获与指令写入**：
   - 侦测到晶晨 `firmware version` 响应后立即锁定状态；
   - 执行 `setenv bootdelay 15`：将 U-Boot 开机倒计时由 0 延长至 15 秒（为后续可能的串口调试留出从容操作时间）；
   - 执行 `setenv boot_part boot0`：指定开机从 0 号槽位启动；
   - 执行 `saveenv`：将修改后的环境变量牢固写盘；
   - 执行 `partition system0 <固件>`：流式烧录固件到 `system0` 分区（通常耗时约 1 分钟）；
4. **提示完工**：拔掉数据线与电源，重新插电开机即可进入新系统。

---

### 3. 交互式多功能工具箱 (`xiaoai-usb-tool.sh`)
集成式维护与调试控制台，适合开发者或需要深度排障的高级用户。

```bash
sudo ./xiaoai-usb-tool.sh
```

**功能菜单说明**：
```text
========== L06A/LX06 USB 工具 ==========
 连接状态: 在线 / 离线
----------------------------------------
 1) 连接设备 (抓烧录窗口)      -> 手动探测或触发上电捕获
 2) 设置 UBOOT 等待时间        -> 自由设定 bootdelay 参数
 3) 查看 UBOOT 环境变量        -> 打印全部 printenv 变量
 4) 备份全部分区到电脑        -> 导出 NAND 全部分区
 5) 备份单个分区              -> 指定导出单个分区（如 data 或 tpl）
 6) 刷写固件到 system0        -> 自动刷入固件并切至 boot0 启动
 7) 刷写自定义镜像到指定分区  -> 高级写入（如自定义 boot0 内核）
 8) 设置启动分区              -> 在 boot0 与 boot1 双系统槽位之间无损切换
 9) 执行自定义 UBOOT 命令      -> 直接下发任意 bulkcmd 指令
 0) 退出
========================================
```

---

### 4. U-Boot 命令直通终端 (`uboot-cmd.sh`)
晶晨平台独有的协议通道：在不需要焊接 TTL 飞线的情况下，通过 USB 烧录线直通 U-Boot 的交互命令行。

- **交互 Shell 模式**：
  ```bash
  sudo ./uboot-cmd.sh
  ```
  脚本捕获设备后，会呈现 `uboot>` 提示符，可直接输入并执行 `printenv`、`help` 等指令。输入 `exit` 或 `quit` 退出。
- **单条/多条批处理模式**：
  ```bash
  sudo ./uboot-cmd.sh "printenv boot_part" "printenv bootdelay"
  ```

---

### 5. TTL 串口自动打断工具 (`ttl-uboot.py`)
若你焊接了主板上的串口飞线（TX/RX/GND，默认波特率 115200）：
```bash
python3 ttl-uboot.py /dev/ttyUSB0 115200
```
- **核心逻辑**：针对原厂 `bootdelay=0` 导致人工按回车难以拦截进 U-Boot 的痛点，程序在上电时以 0.5s 周期持续连发回车键；一旦检测到控制台输出 `=>` 提示符，自动停止连发并平滑转为双向透明终端；
- **会话留痕**：控制台全部输入输出会自动同步记录到 `logs/` 目录下的日志文件中。按 `Ctrl + ]` 随时退出。

---

## 七、双系统槽位机制与一秒防砖回滚

得益于 Amlogic SoC 与小爱音箱底层的 A/B 槽位隔离设计，本项目具有物理级安全冗余：

- **槽位 0 (自定义区)**：`boot0` (内核) + `system0` (文件系统) —— **由本工具刷写修改版固件**；
- **槽位 1 (原厂备份区)**：`boot1` (内核) + `system1` (出厂系统) —— **全流程保持原封不动**。

### 遇到任何异常或希望恢复官方出厂系统：

#### 方法 A：一条命令快速回滚
在电脑上执行：
```bash
sudo ./uboot-cmd.sh "setenv boot_part boot1" "saveenv"
```
拔掉 USB 线与电源，重新插电，音箱即可瞬间从原厂槽位 `system1` 启动恢复。

#### 方法 B：通过交互菜单回滚
运行 `sudo ./xiaoai-usb-tool.sh`，在主菜单选择 `8) 设置启动分区`，输入 `boot1` 即可。

---

## 八、刷机后连接与验证

1. **开机等待**：
   刷机成功拔掉数据线重新上电后，音箱启动需要约 1 ~ 2 分钟加载网络配置。
2. **确认 IP 地址**：
   可以在路由器后台查找名为 `xiaomi` 或新加入局域网的 IP 地址。
3. **SSH 登录**：
   现代 Linux 终端默认禁用了旧版 RSA 密钥握手，连接时需显式启用算法：
   ```bash
   ssh -o HostKeyAlgorithms=+ssh-rsa root@<音箱的局域网IP>
   ```
   - **默认密码**：依你所下载制作的 Open-XiaoAI 镜像配置而定（官方默认通常为 `open-xiaoai`）；
   - **安全建议**：登录成功后，第一时间执行 `passwd` 更改默认密码。

---

## 九、常见问题排查 (FAQ)

### Q1: 提示 `未检测到设备` 或超时无法捕获窗口？
1. **排查线缆**：90% 的连接失败是因为误用了两芯纯充电线。请换用手机原装或其他经过数据传输验证的 4 芯线；
2. **观察系统总线日志**：
   在 Linux 主机开启另一个终端监控：`dmesg -w`。拔掉电源重新插上时，系统日志必须出现类似以下 USB 枚举记录：
   ```text
   usb 1-1: new high-speed USB device number ... using xhci_hcd
   usb 1-1: New USB device found, idVendor=1b8e, idProduct=0cee, bcdDevice= 0.07
   usb 1-1: Product: GX-CHIP
   usb 1-1: Manufacturer: Amlogic
   ```
3. **硬件强制烧录模式**：
   个别批次的硬件可能关闭了默认上电 USB 轮询，此时只需在**按住音箱顶部的 `PLAY`（播放/暂停）按键不放的同时插上电源**，即可强制硬件跳入 Amlogic 烧录模式。

### Q2: 报错 `error while loading shared libraries: libusb-0.1.so.4`？
说明系统中缺少 `libusb-compat` 库，且脚本未能在 `./lib` 目录中完成备用加载。
- Arch/Manjaro: `sudo pacman -S libusb-compat`
- Debian/Ubuntu: `sudo apt install -y libusb-0.1-4`

### Q3: 刷机提示失败（Flash Fail）？
- 不要拔掉电源！因为当前的 USB 烧录会话仍然有效，检查是否镜像路径错误或固件异常，修正命令后直接重新执行 `./flash-l06a.sh` 即可重试；
- 如果想彻底放弃本次刷写，直接运行 `./uboot-cmd.sh "setenv boot_part boot1" "saveenv"` 回滚原厂。
