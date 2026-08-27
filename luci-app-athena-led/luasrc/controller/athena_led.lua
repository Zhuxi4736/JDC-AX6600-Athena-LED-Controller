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

    -- 3. 后端 action (状态查询 / 读取映射 / 保存映射 / 启用服务)
    entry({"admin", "services", "athena_led", "status"},   call("act_status")).leaf = true
    entry({"admin", "services", "athena_led", "pet_load"}, call("act_pet_load")).leaf = true
    entry({"admin", "services", "athena_led", "pet_save"}, call("act_pet_save")).leaf = true
    entry({"admin", "services", "athena_led", "pet_enable"}, call("act_pet_enable")).leaf = true
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
                if cmd:find("athena%-led") then
                    e.running = true
                    e.pid = pid
                end
            end
        end
    end
    if not e.running then
        local pid = sys.exec("pgrep -f /usr/bin/athena-led | head -n 1")
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

-- 启用并启动核心服务 (写入 uci enabled=1)
function act_pet_enable()
    local en = http.formvalue("enabled") or "1"
    uci:set("athena_led", "general", "enabled", en)
    uci:commit("athena_led")
    sys.call("/etc/init.d/athena_led enable >/dev/null 2>&1")
    sys.call("/etc/init.d/athena_led restart >/dev/null 2>&1")
    http.prepare_content("application/json")
    http.write('{"ok":true}')
end
