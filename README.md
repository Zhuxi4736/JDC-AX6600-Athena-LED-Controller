# OpenWrt Athena LED Controller (Enhanced)

[English](#english) | [简体中文](#简体中文)


---

<a name="简体中文"></a>
## 🇨🇳 简体中文介绍

**适用于京东云无线宝 AX6600 (雅典娜) 的终极 LED 点阵屏控制器。**

本项目基于 `haipengno1` 和 `NONGFAH` 的作品进行了深度开发。我们将核心程序与 LuCI 界面整合，并实现了一些新功能。

### ✨ 核心功能
* **网络监控**: 实时上下行网速、WAN IP、ARP 在线设备数、连接数、TCP 延迟。
* **系统状态**: CPU/内存占用率、系统运行时间、温度监控与**超温闪烁告警**。
* **日历与天气**: 当地天气、**农历日期**、**日出日落**、倒数日 (D-Day)。
* **极致休眠**: 零负载精准休眠 + **夜间自动降亮度**。
* **自动化集成**: **MQTT 消息上屏** (Home Assistant)、本机控制接口 (`nc` 一行指令插播文本/切台/调亮度)。
* **全固件兼容**: GPIO 双后端自动适配 (官方 OpenWrt / QWRT / iStoreOS),LuCI JS 界面。
* **交互**: 物理按键短按切台 / 双击回首页 / 长按息屏。

### 🐾 新增：AI 虚拟宠物 (v2.6.0)
把你的雅典娜路由器变成一只「会反映 AI 心情的小机器人」——屏幕就是它的脸。

* **用途**：让路由器 LED 屏显示可自定义的像素表情 / 状态（CPU 占用率、上下行网速、时间、文字、GIF 转的像素动画）。由外部程序（如 AI 助手 Hermes 的生命周期状态）通过 HTTP 一行指令驱动，让屏幕「反映心情」。
* **完全自定义**：状态→显示内容的映射写在 `/etc/athena_led/pet.json`（网页可直接编辑，零命令行）。例如：
  ```json
  {
    "thinking": "pet_thinking.bin",
    "failed":   "pet_failed.bin",
    "angry":    "cpu",
    "idle":     "time"
  }
  ```
  - 值可以是 **动画文件**（`pet_*.bin`，27×5 单色像素动画，由 GIF 转来）；
  - 也可以是 **模块名**：`cpu` / `updl`(上下行) / `mem` / `load` / `time`(时间)；
  - 或 **任意文字**。
* **HTTP 转发**：路由器侧常驻 `athena-pet-relay`（LuCI 启动项可管），监听 LAN `:8080`，把请求翻译成 LED 控制指令：
  ```bash
  curl -X POST http://路由器IP:8080/pet/thinking   # 显示"思考"表情
  curl -X POST http://路由器IP:8080/petb/failed    # 先报幕"FAILED"再切裂开脸
  curl -X POST http://路由器IP:8080/petidle/60     # 空闲60秒后回 idle 态
  ```
* **图形化管理**：LuCI → Athena LED → 🐾 虚拟宠物，网页编辑映射表、保存即重载，无需碰命令行。
* **预置 8 种表情**：thinking / run / wave / jump / failed / love / waiting / idle（由 `tools/gen_pet_bins.py` 生成，`tools/gif2bin.py` 可把任意 GIF 转成新表情 `.bin`）。

### 📥 安装方法 (推荐)

请根据您的 OpenWrt 系统版本选择对应的安装方式，无需自行编译。

> 🌟 **v2.3.0 起拆分为两个软件包**：`athena-led`(核心驱动) + `luci-app-athena-led`(Web 界面)，**两个都要装**。

#### 🅰️ 方案一：OpenWrt 23.05 及旧版 (使用 `.ipk`)
适用于大多数目前的稳定版固件。

1.  前往 **[Releases (发行版)](../../releases)** 页面下载最新的 `athena-led_*.ipk` 和 `luci-app-athena-led_*.ipk` 两个文件。
2.  上传至路由器 `/tmp/` 目录。
3.  执行安装命令：
    ```bash
    opkg install /tmp/athena-led_*.ipk /tmp/luci-app-athena-led_*.ipk
    ```

#### 🅱️ 方案二：OpenWrt 24.x / Snapshot (使用 `.apk`)
适用于最新使用 `apk` 包管理器的固件。

1.  前往 **[Releases (发行版)](../../releases)** 页面下载最新的 `athena-led_*.apk` 和 `luci-app-athena-led_*.apk` 两个文件。
2.  上传至路由器 `/tmp/` 目录。
3.  执行安装命令 (**必须添加 `--allow-untrusted` 参数**)：
    ```bash
    apk add --allow-untrusted /tmp/athena-led_*.apk /tmp/luci-app-athena-led_*.apk
    ```

🎉 **配置**：安装完成后刷新网页，进入 **服务 (Services) -> Athena LED** 进行配置。

### 🏗️ 开发者 / 固件编译
如果您是固件开发者，或者希望从源码编译：
* **Rust 核心**: 请参阅 [athena-led/README.md](athena-led/README.md)
* **LuCI 界面**: 请参阅 [luci-app-athena-led/README.md](luci-app-athena-led/README.md)


---

<a name="english"></a>
## 🇬🇧 English Description

**The ultimate LED matrix controller for JDCloud AX6600 (Athena), featuring a comprehensive LuCI interface and extensive system monitoring.**

This project is a heavily modified fork based on `haipengno1` and `NONGFAH`. We have integrated the backend and frontend into a single repository and added significant new features.

### ✨ Key Features
* **Network**: Real-time Upload/Download speed, WAN IP, ARP Device Count.
* **System**: CPU/RAM usage, Uptime, Temperature.
* **Sleep Mode**: **Zero-Load Precision Sleep** (0% CPU usage during sleep).
* **Weather**: Local weather integration.
* **Stability**: Fixed traffic speed bugs and UTF-8 text crashes.

### 📥 Installation (Recommended)

Please choose the appropriate installation method based on your OpenWrt version. No compilation is required.

#### 🅰️ Option 1: OpenWrt 23.05 & Older (Use `.ipk`)
For current stable releases using `opkg`.

1.  Go to the **[Releases](../../releases)** page and download the latest `luci-app-athena-led_*.ipk` file.
2.  Upload it to your router's `/tmp/` directory.
3.  Run the installation command:
    ```bash
    opkg install /tmp/luci-app-athena-led_*.ipk
    ```

#### 🅱️ Option 2: OpenWrt 24.x / Snapshot (Use `.apk`)
For the latest development snapshots using the new `apk` package manager.

1.  Go to the **[Releases](../../releases)** page and download the latest `luci-app-athena-led_*.apk` file.
2.  Upload it to your router's `/tmp/` directory.
3.  Run the installation command (**Must include `--allow-untrusted` flag**):
    ```bash
    apk add --allow-untrusted /tmp/luci-app-athena-led_*.apk
    ```

🎉 **Configuration**: After installation, refresh the web interface and go to **Services -> Athena LED** to configure.

### 🏗️ For Developers / Custom Firmware
If you are building your own OpenWrt firmware or want to modify the source:
* **Rust Core**: See [athena-led/README.md](athena-led/README.md)
* **LuCI App**: See [luci-app-athena-led/README.md](luci-app-athena-led/README.md)


---

## 📜 Credits / 致谢

* **Core Logic**: Based on [NONGFAH/athena-led](https://github.com/NONGFAH/athena-led).
* **LuCI Base**: Based on [haipengno1/luci-app-athena-led](https://github.com/haipengno1/luci-app-athena-led).
* **Enhanced Features**: Implemented by **unraveloop** & Team (Network/System monitors, Weather, Precision Sleep, etc.).

## 📄 License

Licensed under the **Apache License 2.0**.
