# JDC AX6600 (雅典娜) LED 控制器 · AI 虚拟宠物版

把京东云无线宝 AX6600（雅典娜）路由器正面那块 27×5 点阵 LED 屏，变成一只**会反映 AI 心情的桌面小机器人**——路由器本身是身体，屏幕是它的脸。

本项目在开源 LED 控制器基础上做了深度重构：核心驱动 + Web 界面整合为单一仓库，并新增 **AI 虚拟宠物** 功能层。路由器刷好固件后，无需命令行，网页上传安装即可使用。

---

## 这版做了什么（创新点）

**1. AI 虚拟宠物 —— 让屏幕"有情绪"**

这是本项目最核心的差异点。屏幕不再只是滚动显示系统指标，而是可以被外部程序（如 AI 助手 Hermes 的生命周期状态）驱动，显示可自定义的像素表情：

- AI 进入思考 → 屏幕切到"思考脸"
- AI 任务失败 → 屏幕切到"裂开脸"并调亮
- AI 闲置超时 → 自动回到时钟 / CPU / 网速 / 任意你设定的画面

状态到画面的映射完全由你定义，写在路由器的 `pet.json` 里，网页即可编辑。

**2. 全图形化，零命令行**

所有配置（轮播内容、宠物映射、表情上传）都在 LuCI 网页完成。用户从安装到日常调整，不需要碰一次终端。

**3. 一键云编译**

仓库自带 GitHub Actions 工作流：fork 后点一下 `Run workflow`，云端自动编译出适配你固件的 `.ipk` 安装包，下载即装。无需在本机配置 Rust 工具链或 OpenWrt SDK。

**4. 多固件兼容**

GPIO 双后端自动适配（字符设备 `/dev/gpiochipN` 优先，sysfs 回退），覆盖官方 OpenWrt / QWRT / iStoreOS 等不同内核的固件，不写死 GPIO 编号。

---

## 功能总览

**AI 虚拟宠物（新增）**

- 状态 → 显示内容映射，写在 `/etc/athena_led/pet.json`，网页可编辑。例如：

  ```json
  {
    "thinking": "pet_thinking.bin",
    "failed":   "pet_failed.bin",
    "angry":    "cpu",
    "idle":     "time"
  }
  ```

  - 值可以是**像素动画文件**（`pet_*.bin`，27×5 单色，由 GIF 转换而来）
  - 也可以是**数据模块名**：`cpu` / `updl`（上下行）/ `mem` / `load` / `time`（时间）
  - 或**任意文字**

- HTTP 转发：路由器侧常驻 `athena-pet-relay`（LuCI 启动项可管），监听 LAN `:8080`，把请求翻译成 LED 控制指令：

  ```bash
  curl -X POST http://路由器IP:8080/pet/thinking   # 显示"思考"表情
  curl -X POST http://路由器IP:8080/petb/failed    # 先报幕"FAILED"再切裂开脸
  curl -X POST http://路由器IP:8080/petidle/60     # 空闲 60 秒后回 idle 态
  ```

- 预置 8 种表情：thinking / run / wave / jump / failed / love / waiting / idle
  （由 `tools/gen_pet_bins.py` 生成；`tools/gif2bin.py` 可把任意 GIF 转成新表情）

**系统监控（原有，已增强）**

- 网络：实时上下行网速、WAN IP、ARP 在线设备数、连接数、TCP 延迟
- 系统：CPU / 内存占用率、运行时间、温度监控与超温闪烁告警
- 日历天气：当地天气、农历日期、日出日落、倒数日
- 精准休眠：零负载休眠 + 夜间自动降亮度
- 自动化：MQTT 消息上屏（Home Assistant）、本机控制接口（`nc` 一行指令插播 / 切台 / 调亮度）
- 物理按键：短按切台 / 双击回首页 / 长按息屏

---

## 安装

> 从 v2.3.0 起拆分为两个包：`athena-led`（核心驱动）+ `luci-app-athena-led`（Web 界面），**两个都要装**。

### 方式一：下载编译好的包（推荐）

1. 前往仓库 **Releases** 页面，下载最新的 `athena-led_*.ipk` 和 `luci-app-athena-led_*.ipk`
2. 上传到路由器 `/tmp/`
3. 安装：

   ```bash
   opkg install /tmp/athena-led_*.ipk /tmp/luci-app-athena-led_*.ipk
   ```

### 方式二：自己云编译

fork 本仓库 → **Actions** → `Build Chain` → `Run workflow`，等待完成后从 Artifacts 下载 `.ipk`。

### 启用

安装后刷新网页，进入 **服务 (Services) → Athena LED** 配置；虚拟宠物在 **🐾 虚拟宠物** 分区设置，转发服务在 **系统 → 启动项** 中开启 `athena-pet-relay`。

---

## 致谢

- 核心逻辑基于 [NONGFAH/athena-led](https://github.com/NONGFAH/athena-led)
- LuCI 界面基于 [haipengno1/luci-app-athena-led](https://github.com/haipengno1/luci-app-athena-led)
- 监控 / 天气 / 精准休眠等增强由 unraveloop 与原作者实现
- AI 虚拟宠物功能层为本仓库新增

## 许可证

Apache License 2.0

---

## English

A complete LED matrix controller for the JDCloud AX6600 (Athena) router, with a built-in **AI Virtual Pet** layer: the router's 27×5 dot-matrix screen becomes the "face" of a desktop companion that reflects an AI agent's mood (thinking / done / failed / idle) through customizable pixel animations or live system data (CPU, uplink/downlink, clock).

Highlights:

- **AI Virtual Pet**: drive the screen from any external program via a simple HTTP call (`POST /pet/<state>`); state→display mapping is a plain JSON file editable from the web UI — no CLI needed.
- **Zero-CLI setup**: everything (profiles, pet mapping, expression upload) is configured in LuCI.
- **Cloud build**: fork the repo and run the GitHub Actions workflow to get a ready-to-install `.ipk`.
- **Multi-firmware**: dual GPIO backend auto-adapts across official OpenWrt / QWRT / iStoreOS.

Install both `athena-led` and `luci-app-athena-led` packages via `opkg`, then configure under **Services → Athena LED**.

Credits: core based on [NONGFAH/athena-led](https://github.com/NONGFAH/athena-led); LuCI based on [haipengno1/luci-app-athena-led](https://github.com/haipengno1/luci-app-athena-led). Licensed under Apache 2.0.
