# 固件存放目录 (Firmware Directory)

请将从 **[Open-XiaoAI (idootop/open-xiaoai)](https://github.com/idootop/open-xiaoai)** 项目下载或自行构建的 squashfs 补丁固件放置在此目录下。

### 获取方式：
1. **直接下载**：前往 [Open-XiaoAI Releases](https://github.com/idootop/open-xiaoai/releases) 页面，下载对应机型（如 LX06 / OH2P）的打包固件。
2. **源码构建**：根据 Open-XiaoAI 的 [client-patch 文档](https://github.com/idootop/open-xiaoai/tree/main/packages/client-patch) 自行制作 `root_patched.squashfs`。

### 支持的文件命名：
- `*.squashfs`（例如 `LX06_1.94.13_patched.squashfs`、`root_patched.squashfs` 或 `firmware.squashfs`）

> [!NOTE]
> 刷机脚本 `flash-l06a.sh` 与 `xiaoai-usb-tool.sh` 会自动检测该目录下的 `.squashfs` 文件，或支持通过命令行参数直接指定固件完整路径。
