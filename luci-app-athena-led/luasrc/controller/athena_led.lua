-- 🌟 [v2.6.0 / QWRT 兼容] 老架构 Lua controller
-- 作用: 在 Lua dispatcher 固件 (QWRT R26.4.4 / QSDK 12.5 / OpenWrt 19.07 代)
--       上注册菜单并渲染虚拟宠物页。
-- 注意: 不引用 nixio、不使用 CBI、不依赖 luci-compat —— 这些都是 QWRT 上
--       导致管理页崩溃的元凶。宠物页用纯 template + 内嵌 JS 实现。
module("luci.controller.athena_led", package.seeall)

local sys  = require "luci.sys"
local http = require "luci.http"
local uci  = require "luci.model.uci".cursor()

local PET_JSON = "/etc/athena_led/pet.json"
local CFG      = "/etc/config/athena_led"

function index()
    -- 1. 主菜单入口 (Services -> Athena LED)
    entry({"admin", "services", "athena_led"}, firstchild(), _("Athena LED"), 60).dependent = false

    -- 2. 虚拟宠物页 (纯 HTML 模板, 不依赖 CBI/luci-compat)
    entry({"admin", "services", "athena_led", "pet"}, template("athena_led/pet"), _("Virtual Pet"), 1)

    -- 3. 后端 action (状态查询 / 读取映射 / 保存映射 / 启用服务 / 上传动画 / 列出动画)
    entry({"admin", "services", "athena_led", "status"},   call("act_status")).leaf = true
    entry({"admin", "services", "athena_led", "pet_load"}, call("act_pet_load")).leaf = true
    entry({"admin", "services", "athena_led", "pet_save"}, call("act_pet_save")).leaf = true
    entry({"admin", "services", "athena_led", "pet_enable"}, call("act_pet_enable")).leaf = true
    entry({"admin", "services", "athena_led", "pet_list"}, call("act_pet_list")).leaf = true
    entry({"admin", "services", "athena_led", "pet_upload"}, call("act_pet_upload")).leaf = true
    -- 预览/测试: 临时播放某表情或测试屏 (不影响 pet.json, 超时自动回正常轮播)
    entry({"admin", "services", "athena_led", "pet_preview"}, call("act_pet_preview")).leaf = true
    entry({"admin", "services", "athena_led", "stop"}, call("act_stop")).leaf = true
    -- 统一的服务/GPIO 控制入口 (apply=改配置并重启, test=临时测试)
    entry({"admin", "services", "athena_led", "pet_gpio"}, call("act_pet_gpio")).leaf = true
end

-- 运行状态查询
function act_status()
    local e = {}
    e.running = false
    local pf = io.open("/var/run/athena-led.pid", "r")
    if pf then
        local pid = pf:read("*l")
        pf:close()
        if pid and pid:match("^%d+$") then
            local cf = io.open("/proc/" .. pid .. "/cmdline", "r")
            if cf then
                local cmd = cf:read("*a") or ""
                cf:close()
                if cmd:find("/usr/bin/athena%-led") then
                    e.running = true
                    e.pid = pid
                end
            end
        end
    end
    if not e.running then
        local pid = sys.exec("pgrep -x athena-led | head -n 1")
        if pid and pid ~= "" then
            e.running = true
            e.pid = string.gsub(pid, "\n", "")
        end
    end
    http.prepare_content("application/json")
    http.write_json(e)
end

-- 读取现有宠物映射 (原样返回 JSON 文本)
function act_pet_load()
    local c = "{}"
    local f = io.open(PET_JSON, "r")
    if f then
        c = f:read("*a") or "{}"
        f:close()
    end
    if not c or c == "" then c = "{}" end
    http.prepare_content("application/json")
    http.write(c)
end

-- 保存宠物映射 (data = JSON 文本) 并重启服务
function act_pet_save()
    local body = http.formvalue("data") or ""
    if not body or body == "" or not body:match("^%s*{") then
        http.status(400)
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"invalid json"}')
        return
    end
    local f = io.open(PET_JSON, "w")
    if f then
        f:write(body)
        f:close()
    end
    sys.call("/etc/init.d/athena_led restart >/dev/null 2>&1")
    http.prepare_content("application/json")
    http.write('{"ok":true}')
end

-- 纯 Lua base64 解码 (不依赖 nixio, 规避 QWRT 缺失问题; Lua 5.1 兼容, 无位移运算符)
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64rev = {}
for i = 1, #b64chars do b64rev[b64chars:sub(i,i)] = i - 1 end
local function b64decode(data)
    data = data:gsub('[^'..b64chars..'=]', '')
    local out = {}
    local buf = 0
    local bits = 0
    for i = 1, #data do
        local c = data:sub(i,i)
        if c == '=' then break end
        local v = b64rev[c]
        if v then
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out+1] = string.char(math.floor(buf / (2 ^ bits)) % 256)
            end
        end
    end
    return table.concat(out)
end

-- 列出 anim/ 目录下所有 .bin 动画文件名
function act_pet_list()
    local dir = "/etc/athena_led/anim/"
    local list = {}
    sys.call("mkdir -p " .. dir)
    local handle = io.popen("ls " .. dir .. "*.bin 2>/dev/null")
    if handle then
        for file_path in handle:lines() do
            local name = file_path:match("([^/]+%.bin)$")
            if name then list[#list+1] = name end
        end
        handle:close()
    end
    http.prepare_content("application/json")
    http.write_json({ ok = true, files = list })
end

-- 上传动画文件 (.bin) 到 /etc/athena_led/anim/
-- 接收 form: name=文件名(必须以 .bin 结尾), data=base64 编码的 .bin 内容
function act_pet_upload()
    local name = http.formvalue("name") or ""
    local b64  = http.formvalue("data") or ""

    -- 安全校验: 只允许 [字母数字_-.]+.bin, 防止路径穿越
    if not name:match("^[%w_%._%-]+%.bin$") then
        http.status(400)
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"文件名非法，必须以 .bin 结尾且不含特殊字符"}')
        return
    end
    if not b64 or #b64 == 0 then
        http.status(400)
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"文件内容为空"}')
        return
    end

    local data = b64decode(b64)
    if not data or #data == 0 then
        http.status(400)
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"base64 解码失败"}')
        return
    end

    sys.call("mkdir -p /etc/athena_led/anim")
    local path = "/etc/athena_led/anim/" .. name
    local f = io.open(path, "wb")
    if not f then
        http.status(500)
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"写入失败，请检查磁盘"}')
        return
    end
    f:write(data)
    f:close()
    http.prepare_content("application/json")
    http.write('{"ok":true,"path":"' .. path .. '","bytes":' .. #data .. '}')
end

-- 预览/测试: 临时播放某表情 (不影响 pet.json, 播放完超时自动回正常轮播)
-- 接收: spec=文件名(.bin)/模块(cpu等)/文字, secs=秒数(默认10)
--   走 control 接口 showraw 指令 (直接播放任意 spec, 不经过 pet.json)
function act_pet_preview()
    local spec = http.formvalue("spec") or ""
    local secs = tonumber(http.formvalue("secs") or "10") or 10
    if secs < 1 then secs = 1 end
    if secs > 60 then secs = 60 end
    if spec == "" then
        http.status(400)
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"spec 为空"}')
        return
    end
    local port = uci:get("athena_led", "general", "control_port") or "8377"
    if spec == "__stop__" then
        -- 停止预览: 发 home 指令让调度器回到轮播首页
        local out = sys.exec(string.format('echo "home" | nc 127.0.0.1 %s', port))
        http.prepare_content("application/json")
        http.write('{"ok":true,"msg":"已回正常轮播"}')
        return
    end
    -- 构造 spec: .bin 文件名 / 模块 / 文字
    local disp = spec
    if not disp:match("%.bin$") then
        if disp == "cpu" or disp == "updl" or disp == "mem" or disp == "load" or disp == "time" or disp == "clock" then
            disp = "module:" .. (disp == "clock" and "timeBlink" or disp)
        else
            disp = "text:" .. disp
        end
    end
    local out = sys.exec(string.format('echo "showraw %s %d" | nc 127.0.0.1 %s', disp, secs, port))
    http.prepare_content("application/json")
    http.write('{"ok":true,"spec":"' .. disp .. '","secs":' .. secs .. '}')
end

-- 启用并启动核心服务 (写 enabled=1 并 restart)
function act_pet_enable()
    uci:set("athena_led", "general", "enabled", "1")
    uci:commit("athena_led")
    sys.call("/etc/init.d/athena_led enable >/dev/null 2>&1")
    sys.call("/etc/init.d/athena_led restart >/dev/null 2>&1")
    http.prepare_content("application/json")
    http.write('{"ok":true}')
end

-- 停止核心服务 (写 enabled=0 并 stop)
function act_stop()
    uci:set("athena_led", "general", "enabled", "0")
    uci:commit("athena_led")
    sys.call("/etc/init.d/athena_led stop >/dev/null 2>&1")
    sys.call("/etc/init.d/athena_led disable >/dev/null 2>&1")
    http.prepare_content("application/json")
    http.write('{"ok":true}')
end

-- 统一 GPIO / 服务控制入口
-- action=apply&base=432 -> 写 gpio_base 到配置并重启服务
-- action=test&base=432  -> 临时用该 base 启动 5 秒测试显示 (不改配置)
function act_pet_gpio()
    local action = http.formvalue("action") or "test"
    local base = http.formvalue("base") or "auto"
    local port = uci:get("athena_led", "general", "control_port") or "8377"
    local bin = "/usr/bin/athena-led"
    if not sys.exec("test -x " .. bin .. " && echo 1 || echo 0"):match("1") then
        http.prepare_content("application/json")
        http.write('{"ok":false,"msg":"核心程序不存在"}')
        return
    end
    if action == "apply" then
        uci:set("athena_led", "general", "gpio_base", base)
        uci:commit("athena_led")
        sys.call("/etc/init.d/athena_led restart >/dev/null 2>&1")
        http.prepare_content("application/json")
        http.write('{"ok":true,"base":"' .. base .. '","msg":"已应用 gpio_base=' .. base .. ' 并重启"}')
        return
    end
    -- test: 临时用该 base 启动约 5 秒 (timeout 自动退出), 测试完自动重启正常服务
    local test_arg = string.format('killall athena-led 2>/dev/null; sleep 1; timeout 6 %s --gpio-base %s --light-level 5 --profile "timeBlink#5" --control-port %s >/dev/null 2>&1 & sleep 7; /etc/init.d/athena_led restart >/dev/null 2>&1 &',
        bin, base, port)
    sys.call(test_arg)
    http.prepare_content("application/json")
    http.write('{"ok":true,"base":"' .. base .. '","msg":"已用 gpio_base=' .. base .. ' 测试约5秒, 之后自动恢复正常运行"}')
end
