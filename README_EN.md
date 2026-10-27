# XiaoAi Speaker Native Linux USB Flashing & Low-Level Toolset

A native Linux USB flashing, NAND backup, dual-slot partition switching, and U-Boot communication toolkit tailored for **Xiaomi Sound (L06A)**, **XiaoAi Speaker Pro (LX06)**, and **Xiaomi Smart Speaker Pro (OH2P)**.

[中文文档 (README.md)](README.md)

---

## Disclaimer & Attribution

> [!IMPORTANT]
> - **Tooling Purpose Only**: This project focuses purely on delivering a **native, dependency-light, command-line** USB flashing workflow, full NAND extraction mechanism, and U-Boot communication pipeline on Linux.
> - **No Third-Party Firmwares or Patches Included**: In accordance with open-source compliance and intellectual property boundaries, this repository does **NOT** redistribute any modified firmware images (`*.squashfs`) or upstream system patch source files.
> - **Upstream Attribution & Credits**:
>   - Firmware patch recipes, Dropbear SSH integration, OTA interception logic, and smart voice extensions belong to the **[Open-XiaoAI (idootop/open-xiaoai)](https://github.com/idootop/open-xiaoai)** project by [@idootop](https://github.com/idootop).
>   - Low-level Amlogic Linux USB burning communication is powered by the open-source suite **[@khadas/utils (aml-flash-tool)](https://github.com/khadas/utils/tree/master/aml-flash-tool)**.

---

## Table of Contents
- [1. Supported Devices & Hardware Architecture](#1-supported-devices--hardware-architecture)
- [2. Key Features & Advantages](#2-key-features--advantages)
- [3. Obtaining Firmware (from Open-XiaoAI)](#3-obtaining-firmware-from-open-xiaoai)
- [4. Environment Setup & Dependencies](#4-environment-setup--dependencies)
- [5. Hardware Connection & Wiring](#5-hardware-connection--wiring)
- [6. Detailed Usage Guide](#6-detailed-usage-guide)
  - [1. Recommended Pre-flash Step: Full NAND Backup (`backup-all.sh`)](#1-recommended-pre-flash-step-full-nand-backup-backup-allsh)
  - [2. One-Click Automated Flashing (`flash-l06a.sh`)](#2-one-click-automated-flashing-flash-l06ash)
  - [3. Interactive Utility Suite (`xiaoai-usb-tool.sh`)](#3-interactive-utility-suite-xiaoai-usb-toolsh)
  - [4. U-Boot Command Direct Channel (`uboot-cmd.sh`)](#4-u-boot-command-direct-channel-uboot-cmdsh)
  - [5. Automated TTL Break Tool (`ttl-uboot.py`)](#5-automated-ttl-break-tool-ttl-ubootpy)
- [7. Dual-Slot Partition Scheme & Instant Rollback](#7-dual-slot-partition-scheme--instant-rollback)
- [8. Post-Flash Verification & SSH Login](#8-post-flash-verification--ssh-login)
- [9. Troubleshooting & FAQ](#9-troubleshooting--faq)

---

## 1. Supported Devices & Hardware Architecture

| Device Model | Marketing Name | SoC (Processor) | Storage Type & Size | Internal Debug Port |
| :--- | :--- | :--- | :--- | :--- |
| **L06A** | Xiaomi Sound Smart Speaker | Amlogic A113X (Quad-Core Cortex-A53) | 128MB SLC NAND | Micro USB service port on mainboard |
| **LX06** | XiaoAi Speaker Pro | Amlogic A113X (Quad-Core Cortex-A53) | 128MB SLC NAND | Micro USB service port on mainboard |
| **OH2P** | Xiaomi Smart Speaker Pro | Amlogic A113X (Quad-Core Cortex-A53) | 128MB SLC NAND | External Type-C / Internal port |

### NAND Flash Partition Layout (128MB Total)
The Amlogic SoC platform utilizes an A/B dual-slot redundancy design:
```text
[bootloader: 2MB] -> [tpl: 8MB] -> [boot0: 6MB] -> [boot1: 6MB] -> [system0: 40MB] -> [system1: 40MB] -> [data: 20MB]
```

---

## 2. Key Features & Advantages

| Feature Dimension | Original Open-XiaoAI Upstream Guide | This Toolset (xiaoai-flash-linux) |
| :--- | :--- | :--- |
| **Host OS Support** | Mainly Windows (requires Git Bash & driver installer) and macOS | **Pure Native Linux**, supporting all major distributions |
| **Driver Overhead** | Requires proprietary Windows Amlogic driver setup | **Zero external driver installation**, communicates directly via kernel `libusb` |
| **USB Window Catching** | Manual command execution, prone to timing misses | **200ms high-frequency handshake loop**, 100% reliable capture on power-up |
| **Fail-Safe Rollback** | Writes to `system0` but lacks automated one-click slot revert tools | **One-click dual-slot switching**, leaving `system1` intact for instant factory recovery |
| **Full Storage Backup** | No automated partition dump scripts provided | **One-click complete extraction of all 7 NAND partitions** |
| **U-Boot Command Shell** | Typically requires soldering physical TTL UART jumper wires | **USB bulkcmd pass-through**, execute U-Boot commands without wire soldering |

---

## 3. Obtaining Firmware (from Open-XiaoAI)

Before flashing, prepare a compatible `.squashfs` rootfs image built for your specific speaker model.

### Acquisition Channels:
1. **Download Pre-built Releases**:
   Visit the [Open-XiaoAI Releases](https://github.com/idootop/open-xiaoai/releases) page and download the archive for your model (e.g. `LX06_1.94.13_patched.squashfs` or `root_patched.squashfs`).
2. **Build from Source**:
   Follow instructions in [packages/client-patch](https://github.com/idootop/open-xiaoai/tree/main/packages/client-patch). Upstream patches include:
   - `01-ssh.patch`: Drops in Dropbear SSH server.
   - `02-login.patch`: Configures root account credentials (default: `open-xiaoai`).
   - `03-ota.patch`: Disables silent OTA updating routines in `/bin/ota`, `/bin/flash.sh`, and wireless scripts.
   - `04-start.patch`: Sets up service autorun.

### Storage Location:
Place your squashfs file in the `firmware/` directory of this repo (the scripts automatically discover any `.squashfs` file placed here), or supply its absolute path as an argument when executing scripts.

---

## 4. Environment Setup & Dependencies

### 1. Install `libusb-compat` (Required)
The underlying `update` binary relies on `libusb-0.1`.

- **Arch Linux / Manjaro**:
  ```bash
  sudo pacman -S libusb-compat
  ```
- **Ubuntu / Debian**:
  ```bash
  sudo apt update
  sudo apt install -y libusb-0.1-4
  # If package is missing on newer distros: sudo apt install -y libusb-compat-0.1-4
  ```
- **Fedora / RHEL / CentOS**:
  ```bash
  sudo dnf install -y libusb-compat-0.1
  ```
- **openSUSE**:
  ```bash
  sudo zypper in libusb-0_1-4
  ```

> [!NOTE]
> A compiled 64-bit `libusb-0.1.so.4` is pre-bundled in the `lib/` directory as an automatic fallback, which the scripts load via `LD_LIBRARY_PATH`.

### 2. Configure udev Rules (Optional, for non-root execution)
To enable regular users without `sudo` privileges to interact with Amlogic USB bootloader devices:
```bash
sudo cp udev/99-amlogic.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 3. Python Serial Library (Only needed when running `ttl-uboot.py`)
```bash
pip install pyserial
# Or via package manager: sudo pacman -S python-pyserial / sudo apt install python3-serial
```

---

## 5. Hardware Connection & Wiring

1. **Cable Requirement**:
   - Use a high-quality **Micro USB data cable** (or Type-C cable for newer speaker variants).
   - **Crucial Warning**: Never use a 2-wire "charging-only" cable. The cable must have all 4 wires (VBUS, GND, D+, D-) connected.
2. **Accessing the Debug Interface**:
   - **Xiaomi Sound (L06A) / XiaoAi Speaker Pro (LX06)**:
     Peel off the rubber anti-slip foot at the bottom, unscrew the base screws, and remove the bottom shell. Near the top-left edge of the circuit board is the **Micro USB service port**. Connect your USB data cable between this port and your Linux host.
   - **Xiaomi Smart Speaker Pro (OH2P)**:
     If equipped with an external Type-C service port at the bottom, plug in directly.
3. **Power Adapter**:
   - The device requires substantial power on boot. **The USB cable carries data only; do not attempt to power the unit solely via USB.** Always plug in the official DC wall adapter.

---

## 6. Detailed Usage Guide

### 1. Recommended Pre-flash Step: Full NAND Backup (`backup-all.sh`)
Before writing any data to the NAND flash, **it is strongly recommended to dump all original factory partitions**.

```bash
# Backs up to backups/backup-<timestamp>/ by default
sudo ./backup-all.sh

# Or specify a custom output directory:
sudo ./backup-all.sh /path/to/my_backup_dir
```

**How it works**:
1. Prompts you to cycle speaker DC power;
2. Once the bootloader window is detected, uses `update mread` to sequentially extract raw images for:
   - `bootloader.bin` (2MB)
   - `tpl.bin` (8MB)
   - `boot0.bin` (6MB) / `boot1.bin` (6MB)
   - `system0.bin` (40MB) / `system1.bin` (40MB)
   - `data.bin` (20MB)

---

### 2. One-Click Automated Flashing (`flash-l06a.sh`)
The quickest, most reliable automated flashing workflow:

```bash
# Automatically finds .squashfs file in firmware/ directory
sudo ./flash-l06a.sh

# Or supply an explicit path to your squashfs file:
sudo ./flash-l06a.sh /path/to/my_firmware.squashfs
```

**Step-by-step Execution**:
1. Validates the existence and size of the firmware (must not exceed the 40MB `system0` hardware limit);
2. Prompts you to unplug and re-plug the DC power adapter;
3. Automatically hooks the Amlogic boot window within 120 seconds;
4. Configures U-Boot parameters:
   - `setenv bootdelay 15` (extends autoboot countdown from 0 to 15s for future debugging);
   - `setenv boot_part boot0` (points default boot slot to slot 0);
   - `saveenv` (persists variables into NAND);
   - `partition system0 <firmware>` (flashes the rootfs into `system0`);
5. Once completed, disconnect the USB cable and power-cycle the speaker to boot into your new system.

---

### 3. Interactive Utility Suite (`xiaoai-usb-tool.sh`)
An all-in-one console suited for diagnostics, backup inspection, and partition management:

```bash
sudo ./xiaoai-usb-tool.sh
```

**Menu Overview**:
```text
========== L06A/LX06 USB Tool ==========
 Connection Status: Online / Offline
----------------------------------------
 1) Connect Device (Scan Burning Window)
 2) Set UBOOT Boot Delay (bootdelay)
 3) Print UBOOT Environment Variables
 4) Backup All Partitions to PC
 5) Backup Single Partition
 6) Flash Firmware to system0 (sets boot0)
 7) Flash Custom Image to Specific Partition
 8) Switch Boot Partition (boot0 <-> boot1)
 9) Execute Custom UBOOT Commands
 0) Exit
========================================
```

---

### 4. U-Boot Command Direct Channel (`uboot-cmd.sh`)
Amlogic's proprietary USB protocol allows issuing U-Boot commands directly over the USB burning cable without soldering UART wires.

- **Interactive Shell Mode**:
  ```bash
  sudo ./uboot-cmd.sh
  ```
  Presents a `uboot>` prompt where you can execute commands like `printenv`, `help`, etc. Type `exit` or `quit` to leave.
- **Batch Mode**:
  ```bash
  sudo ./uboot-cmd.sh "printenv boot_part" "printenv bootdelay"
  ```

---

### 5. Automated TTL Break Tool (`ttl-uboot.py`)
If you have soldered physical serial jumper wires (TX/RX/GND @ 115200 baud):
```bash
python3 ttl-uboot.py /dev/ttyUSB0 115200
```
- **Feature**: Bypasses the factory `bootdelay=0` lock by continuously flooding Enter every 0.5s during boot. Once the `=>` U-Boot prompt is detected, it halts flooding and transitions to a clean serial console.
- **Logging**: All session input/output is logged to the `logs/` directory. Exit with `Ctrl + ]`.

---

## 7. Dual-Slot Partition Scheme & Instant Rollback

Thanks to the hardware A/B partitioning scheme on Amlogic A113X, flashing this device carries near-zero bricking risk:

- **Slot 0 (Custom)**: `boot0` (Kernel) + `system0` (Rootfs) — **Targeted by this flashing tool**;
- **Slot 1 (Factory Backup)**: `boot1` (Kernel) + `system1` (Rootfs) — **Left untouched at all times**.

### Reverting to Original Factory Firmware:

#### Method A: Single Command Revert
Run on your Linux computer:
```bash
sudo ./uboot-cmd.sh "setenv boot_part boot1" "saveenv"
```
Unplug the USB and DC power cable, then plug DC power back in. The speaker will immediately boot from the stock `system1` slot.

#### Method B: Via Interactive Menu
Launch `sudo ./xiaoai-usb-tool.sh`, select option `8) Switch Boot Partition`, and enter `boot1`.

---

## 8. Post-Flash Verification & SSH Login

1. **Bootup Time**:
   After flashing, disconnect USB and re-apply DC power. Allow 1 to 2 minutes for network initialization.
2. **Locate Device IP**:
   Check your router's DHCP client table for hostnames matching `xiaomi` or newly connected devices.
3. **SSH Access**:
   Modern Linux distributions disable the legacy RSA key handshake by default. Connect with:
   ```bash
   ssh -o HostKeyAlgorithms=+ssh-rsa root@<SPEAKER_IP>
   ```
   - **Default Password**: Depends on the Open-XiaoAI image you flashed (typically `open-xiaoai`).
   - **Security Advice**: Run `passwd` immediately upon first login to set your personal password.

---

## 9. Troubleshooting & FAQ

### Q1: Tool reports `未检测到设备` (Device not detected) or timeout?
1. **Check the cable**: Most failures are due to using a 2-wire charge-only cable. Test with a verified 4-wire smartphone data cable.
2. **Monitor kernel logs**:
   In a separate terminal, run `dmesg -w`. When plugging in speaker power, you should see:
   ```text
   usb 1-1: new high-speed USB device number ... using xhci_hcd
   usb 1-1: New USB device found, idVendor=1b8e, idProduct=0cee, bcdDevice= 0.07
   usb 1-1: Product: GX-CHIP
   usb 1-1: Manufacturer: Amlogic
   ```
3. **Force Hardware Burning Mode**:
   On stubborn boards, **hold the `PLAY` (play/pause) button down while plugging in the DC power connector**. This forces the Amlogic boot ROM directly into USB burning mode.

### Q2: Error `error while loading shared libraries: libusb-0.1.so.4`?
Indicates missing `libusb-compat` package on your host OS.
- Arch/Manjaro: `sudo pacman -S libusb-compat`
- Debian/Ubuntu: `sudo apt install -y libusb-0.1-4`

### Q3: Flashing fails halfway?
- Do not disconnect the power adapter! The USB burning session is still live. Verify the firmware file path and run `./flash-l06a.sh` again to retry immediately.
- To abort and return safely to factory status, run `./uboot-cmd.sh "setenv boot_part boot1" "saveenv"`.
