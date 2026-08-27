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

## 状态机 + HTTP 信号对接教程（小白向）

**一句话**：路由器 LED 屏幕上显示什么，不再写死，而是由你定义的「状态」决定。每个状态 = 一套显示内容 + 一组触发条件。条件满足就自动切过去，不满足就退回默认状态。**完全不用写代码，配置文件 `/etc/athena_led/states.json` 网页即可编辑。**

### 一、状态（State）长什么样

```json
{
  "id": "doorbell",
  "name": "有人按门铃",
  "is_default": false,
  "priority": 20,
  "persistent": false,
  "hold_secs": 15,
  "trigger": { "logic": "or", "rules": [ { "type": "http", "signal": "doorbell" } ] },
  "substates": [
    { "content": "pet_wave.bin", "mode": "static", "speed": 100, "duration": 5, "leds": { "clock":1,"medal":1,"up":1,"down":1 } },
    { "content": "text:叮咚!", "mode": "type", "speed": 120, "duration": 5, "leds": { "clock":1,"medal":1,"up":1,"down":1 } }
  ]
}
```

字段白话解释：

| 字段 | 含义 | 怎么填 |
|------|------|--------|
| `id` | 状态唯一标识 | 随便起，英文数字，别重复 |
| `name` | 给人看的状态名 | 中文也行 |
| `is_default` | 是不是兜底默认态 | 有且只有**一个**写 `true`，其余 `false` |
| `priority` | 优先级（数字越大越优先） | 默认态填 `0`；重要事件填大数（如门铃 20） |
| `persistent` | 是否常驻 | `true`=触发后一直显示直到别的态抢走；`false`=显示 `hold_secs` 秒后自动退回默认 |
| `hold_secs` | 瞬态持续时间（秒） | `persistent:false` 时才生效 |
| `trigger` | 触发条件 | 见下表；默认态写 `null`（永远兜底） |
| `substates` | 子状态轮播数组 | 每个子态 = 一段显示内容 + 显示方式 + 机身灯 |

子状态 `content` 支持四种写法：
- `pet_xxx.bin` → 像素动画文件（预置在 `/etc/athena_led/anim/`，也可网页上传替换）
- `module:time` / `module:cpu` / `module:updl` / `module:mem` / `module:load` / `module:temp` → 实时数据模块
- `text:你好` → 直接显示文字（中文也行）
- 其它纯文本 → 当作文字显示

子状态 `mode`：`static`（整屏直接显示）/ `type`（逐字打出打字机）/ `flow`（横向滚动）。`speed` 是速度（毫秒，越小越快），`duration` 是这个子态停留几秒后切下一个，`leds` 控制机身四个小灯（clock/medal/up/down，1=亮 0=灭）。

### 二、触发条件（Trigger）一览

每个状态可带多条 `rules`，由 `logic` 决定关系：
- `"or"` → 任意一条满足即触发
- `"and"` → 全部满足才触发

| `type` | 含义 | 常用字段 | 例子 |
|--------|------|----------|------|
| `http` | 收到指定 HTTP 信号 | `signal:"门铃"` | 外部程序喊一声就亮 |
| `cpu` | CPU 占用率 | `op:">"`, `val:80` | CPU 超 80% 显示「忙」 |
| `mem` | 内存占用率 | `op:">"`, `val:90` | 内存超 90% 告警 |
| `load` | 系统负载 | `op:">"`, `val:4` | 负载过高 |
| `temp` | 芯片温度(℃) | `op:">"`, `val:70` | 过热保护提示 |
| `time` | 时间段 | `start:"22:30"`, `end:"07:30"` | 夜间安静态（跨午夜自动处理） |
| `wan` | 外网通断 | `op:"down"` | 断网提示 |
| `device` | 指定设备上下线 | `op:"join"|"up"|"down"`, `mac:"AA:BB:..."` | 某人手机连上 WiFi 就欢迎 |
| `rate` | 实时网速 | `op:">"`, `val:30`, `dir:"down"|"up"` | 下载超 30MB/s 显示下载中 |
| `idle` | 空闲时长(秒) | `val:300` | 5 分钟没人动就休眠态 |
| `ipchange` | 公网 IP 变化 | （无需参数） | 公网 IP 变了提示 |
| `script` | 自定义脚本退出码 | `script:"/path/to/check.sh"` | 脚本返回 0 即触发（用来接任意条件） |

`op` 支持：`>` `<` `>=` `<=` `=`（相等）。数字类比较的是对应指标的实时值。

### 三、HTTP 信号：让任何软件/AI Agent 控制屏幕

「`http` 触发」是连接外部世界最灵活的方式。**任何能发 HTTP 请求的程序**（Home Assistant、Node-RED、Python 脚本、AI Agent、手机快捷指令、甚至是另一个路由器）都能在某一刻喊一声「门铃响了」，LED 立刻切到对应状态。

#### 机制
路由器上的 `athena-led` 程序监听控制端口（默认 `8377`）。你向它发一个 HTTP GET 请求即可投递信号：

```
GET http://路由器IP:8377/signal/<信号名>
```

程序记下「这个信号在最近 60 秒内来过」，然后凡是 `trigger` 里 `type:"http"` 且 `signal` 等于这个名字的状态，就被点燃。

#### 方式 1：一行 curl（最通用）

```bash
# 门铃响了
curl "http://192.168.1.1:8377/signal/doorbell"

# 洗完衣服了
curl "http://192.168.1.1:8377/signal/washer_done"
```

把上面这条命令塞进任何能跑 shell 的地方就行。

#### 方式 2：Home Assistant 自动化

在 HA 的 `automations.yaml` 里，用 `rest_command` 或直接 `shell_command`：

```yaml
# configuration.yaml
shell_command:
  led_signal: "curl -s 'http://192.168.1.1:8377/signal/{{ signal }}'"

# automations.yaml —— 门铃实体变 active 时
- alias: 门铃→LED
  trigger:
    - platform: state
      entity_id: binary_sensor.doorbell
      to: "on"
  action:
    - service: shell_command.led_signal
      data:
        signal: doorbell
```

也可不用 shell，用 HA 原生 `rest` 集成发 GET，效果一样。

#### 方式 3：Python 脚本 / AI Agent

```python
import urllib.request

def led_signal(name: str, router="192.168.1.1", port=8377):
    urllib.request.urlopen(f"http://{router}:{port}/signal/{name}", timeout=3)

# Agent 判断「用户离开家」后：
led_signal("away")
```

任何 LLM Agent（AutoGPT、Dify、Coze、你自己的脚本）只要能执行这行 Python / 这条 curl，就能反向控制路由器屏幕——**这就是「Agent 控制物理设备」的零成本通道**。

#### 方式 4：手机快捷指令（iOS 快捷指令 / Android Tasker）

- iOS：新建「快捷指令」→ 添加「URL」(`http://路由器IP:8377/signal/doorbell`) → 添加「获取 URL 内容」（方法 GET）→ 存到主屏，点一下就亮。
- Android Tasker：事件触发后执行「HTTP Request」GET 到上述地址。

#### 方式 5：接收任意条件（配合 `script` 触发）

如果某个条件你的软件算不出来、但你能写个 shell 脚本判断，就用 `type:"script"`：

```json
{ "type": "script", "script": "/usr/bin/check_baby.sh" }
```

`check_baby.sh` 返回 0（成功）即触发。脚本里你可以查摄像头、查数据库、调第三方 API……**等于把「触发条件」的想象空间完全交给你**。

### 四、把一切串起来（完整例子）

假设你想要这样的体验：

1. 平时：屏幕轮换显示「时间 / 上下行速率 / 温度」（默认态）
2. 晚上 22:30–07:30：显示睡觉表情（夜间态，常驻）
3. CPU 超 80% 或温度超 70℃：显示「思考」表情 + 时钟灯亮（忙态，常驻）
4. 下载超 30MB/s：滚动显示上下行（下载态，瞬态 20 秒后回默认）
5. 门铃响（HA 发 HTTP 信号）：挥手表情 + 全灯亮（瞬态 15 秒）

`states.json` 就这么写（仓库已附示例，装好即用，网页也能改）：

```json
{
  "states": [
    { "id":"idle","name":"默认·悠闲","is_default":true,"priority":0,"persistent":true,"hold_secs":10,
      "trigger":null,
      "substates":[
        {"content":"module:time","mode":"static","speed":100,"duration":5,"leds":{"clock":0,"medal":0,"up":0,"down":0}},
        {"content":"module:updl","mode":"flow","speed":80,"duration":5,"leds":{"clock":0,"medal":0,"up":0,"down":0}},
        {"content":"module:temp","mode":"static","speed":100,"duration":5,"leds":{"clock":0,"medal":0,"up":0,"down":0}}
      ]},
    { "id":"night","name":"夜间·安静","is_default":false,"priority":1,"persistent":true,"hold_secs":10,
      "trigger":{"logic":"or","rules":[{"type":"time","op":"in","start":"22:30","end":"07:30"}]},
      "substates":[{"content":"pet_idle.bin","mode":"static","speed":100,"duration":8,"leds":{"clock":0,"medal":0,"up":0,"down":0}}]},
    { "id":"busy","name":"高负载·忙","is_default":false,"priority":5,"persistent":true,"hold_secs":10,
      "trigger":{"logic":"or","rules":[{"type":"cpu","op":">","val":80},{"type":"temp","op":">","val":70}]},
      "substates":[
        {"content":"pet_thinking.bin","mode":"static","speed":100,"duration":4,"leds":{"clock":1,"medal":0,"up":0,"down":0}},
        {"content":"module:cpu","mode":"type","speed":90,"duration":4,"leds":{"clock":1,"medal":0,"up":0,"down":0}}
      ]},
    { "id":"download","name":"下载中","is_default":false,"priority":6,"persistent":false,"hold_secs":20,
      "trigger":{"logic":"or","rules":[{"type":"rate","op":">","val":30,"dir":"down"}]},
      "substates":[{"content":"module:updl","mode":"flow","speed":70,"duration":6,"leds":{"clock":0,"medal":0,"up":0,"down":1}}]},
    { "id":"doorbell","name":"有人按门铃","is_default":false,"priority":20,"persistent":false,"hold_secs":15,
      "trigger":{"logic":"or","rules":[{"type":"http","signal":"doorbell"}]},
      "substates":[
        {"content":"pet_wave.bin","mode":"static","speed":100,"duration":5,"leds":{"clock":1,"medal":1,"up":1,"down":1}},
        {"content":"text:叮咚!","mode":"type","speed":120,"duration":5,"leds":{"clock":1,"medal":1,"up":1,"down":1}}
      ]}
  ]
}
```

### 五、优先级怎么算（多个状态同时满足谁赢）

每条规则每帧都检查。当多个状态同时「命中」：

- 有效优先级 = `priority` + （若是常驻态 `persistent:true` 则额外 +100）
- **有效优先级最高者胜出**，显示它。
- 没有任何状态命中时，回退到 `is_default:true` 的那个状态。

按上面的例子：门铃（priority 20）来了 → 哪怕正显示「忙」（5+100=105），门铃是瞬态（20+0=20），所以**常驻态压过瞬态**（忙态 105 > 门铃 20）。门铃只会在没有任何常驻态命中时才赢。如果你希望门铃**一定压过一切**，把它的 `priority` 填到 200（200 > 105），或者给它也设 `persistent:true`。

> 小提示：想让某个事件「强制打断一切」，就给它大 priority（如 200）+ `persistent:true`；想让它「只插播一下就走」，就小 priority + `persistent:false` + 短 `hold_secs`。

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
