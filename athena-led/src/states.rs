// ==========================================
// 🗂️ states.rs — 状态机核心 (v2.7.0 重写)
// 每个 State 是一个完整行为包: 触发条件 + 子状态轮换 + 机身灯
// 配置存 /etc/athena_led/states.json
// ==========================================
use crate::monitor::SystemMonitor;
use crate::Args;
use chrono::Local;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Instant;

// ---------------- 数据结构 ----------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LedState {
    #[serde(default)]
    pub clock: u8, // 1=亮 0=灭
    #[serde(default)]
    pub medal: u8,
    #[serde(default)]
    pub up: u8,
    #[serde(default)]
    pub down: u8,
}

impl Default for LedState {
    fn default() -> Self {
        LedState { clock: 0, medal: 0, up: 0, down: 0 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubState {
    // content: xxx.bin / module:cpu / text:你好
    pub content: String,
    #[serde(default = "default_mode")]
    pub mode: String, // static / type / flow
    #[serde(default = "default_speed")]
    pub speed: u64, // ms/帧
    #[serde(default = "default_duration")]
    pub duration: u64, // 子状态停留秒
    #[serde(default)]
    pub leds: LedState,
}

fn default_mode() -> String { "static".into() }
fn default_speed() -> u64 { 100 }
fn default_duration() -> u64 { 5 }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rule {
    pub r#type: String, // http/cpu/mem/load/temp/time/wan/device/rate/idle/ipchange/script
    #[serde(default = "default_op")]
    pub op: String, // > / < / in / = / down / join / up
    #[serde(default)]
    pub val: f64,
    #[serde(default)]
    pub start: String, // time 区间起点 "22:00"
    #[serde(default)]
    pub end: String, // time 区间终点 "07:00"
    #[serde(default)]
    pub dir: String, // rate 方向 up/down
    #[serde(default)]
    pub mac: String, // device MAC
    #[serde(default)]
    pub signal: String, // http 信号名
    #[serde(default)]
    pub script: String, // 脚本路径
}

fn default_op() -> String { ">".into() }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Trigger {
    #[serde(default = "default_logic")]
    pub logic: String, // or / and
    #[serde(default)]
    pub rules: Vec<Rule>,
}

fn default_logic() -> String { "or".into() }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct State {
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub priority: i32,
    #[serde(default)]
    pub persistent: bool, // true=常驻 false=瞬态
    #[serde(default = "default_hold")]
    pub hold_secs: u64, // 瞬态持续秒
    #[serde(default)]
    pub trigger: Option<Trigger>,
    pub substates: Vec<SubState>,
}

fn default_hold() -> u64 { 10 }

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct StatesFile {
    #[serde(default)]
    pub states: Vec<State>,
}

// ---------------- 加载 ----------------

pub fn load_states(path: &str) -> StatesFile {
    match std::fs::read_to_string(path) {
        Ok(s) => match serde_json::from_str::<StatesFile>(&s) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("[states] 解析 {} 失败: {}，使用空配置", path, e);
                StatesFile::default()
            }
        },
        Err(_) => {
            eprintln!("[states] 未找到 {}，使用空配置(旧模式兜底)", path);
            StatesFile::default()
        }
    }
}

// ---------------- 触发评估 ----------------

impl Rule {
    // 返回该 rule 当前是否命中。monitor 提供实时数据，signals 是外部 HTTP 信号集合
    fn matches(&self, m: &mut SystemMonitor, args: &Args, signals: &HashMap<String, Instant>) -> bool {
        match self.r#type.as_str() {
            "http" => {
                if self.signal.is_empty() { return false; }
                // 信号在最近 60 秒内被推过即算命中 (瞬态用)
                if let Some(t) = signals.get(&self.signal) {
                    t.elapsed().as_secs() < 60
                } else { false }
            }
            "cpu" => cmp_val(m.get_cpu_usage(), &self.op, self.val),
            "mem" => cmp_val(m.get_mem_usage(), &self.op, self.val),
            "load" => cmp_val(m.get_load_avg(), &self.op, self.val),
            "temp" => cmp_val(m.get_max_temp(), &self.op, self.val),
            "rate" => {
                let v = if self.dir == "down" { m.get_rx_speed_mbps() } else { m.get_tx_speed_mbps() };
                cmp_val(v, &self.op, self.val)
            }
            "time" => {
                // start-end 区间 (支持跨午夜如 22:00-07:00)
                let now = Local::now().format("%H:%M").to_string();
                in_time_range(&now, &self.start, &self.end)
            }
            "wan" => m.wan_down(), // op 忽略，断开即命中
            "device" => {
                if self.mac.is_empty() { return false; }
                m.device_online(&self.mac)
            }
            "idle" => {
                // 由调度器传 pet_last_active 判断，这里简单返回 false (实际在主循环处理)
                false
            }
            "ipchange" => m.pub_ip_changed(),
            "script" => {
                if self.script.is_empty() { return false; }
                run_script_exit0(&self.script)
            }
            _ => false,
        }
    }
}

impl Trigger {
    pub fn matches(&self, m: &mut SystemMonitor, args: &Args, signals: &HashMap<String, Instant>) -> bool {
        if self.rules.is_empty() { return false; }
        let results: Vec<bool> = self.rules.iter().map(|r| r.matches(m, args, signals)).collect();
        if self.logic == "and" {
            results.iter().all(|x| *x)
        } else {
            results.iter().any(|x| *x)
        }
    }
}

// ---------------- 辅助 ----------------

fn cmp_val(actual: f64, op: &str, val: f64) -> bool {
    match op {
        ">" => actual > val,
        "<" => actual < val,
        ">=" => actual >= val,
        "<=" => actual <= val,
        "=" | "==" => (actual - val).abs() < 0.001,
        _ => false,
    }
}

fn in_time_range(now: &str, start: &str, end: &str) -> bool {
    if start.is_empty() || end.is_empty() { return false; }
    let now_m = hm_to_min(now);
    let s_m = hm_to_min(start);
    let e_m = hm_to_min(end);
    if s_m == e_m { return false; }
    if s_m < e_m {
        now_m >= s_m && now_m < e_m
    } else {
        // 跨午夜: 22:00-07:00
        now_m >= s_m || now_m < e_m
    }
}

fn hm_to_min(hm: &str) -> i32 {
    let parts: Vec<&str> = hm.split(':').collect();
    if parts.len() == 2 {
        let h: i32 = parts[0].parse().unwrap_or(0);
        let m: i32 = parts[1].parse().unwrap_or(0);
        h * 60 + m
    } else { 0 }
}

fn run_script_exit0(path: &str) -> bool {
    use std::process::Command;
    match Command::new("sh").arg("-c").arg(path).status() {
        Ok(s) => s.success(),
        Err(_) => false,
    }
}

// ---------------- 状态选择 ----------------

#[derive(Debug, Clone)]
pub struct ActiveState {
    pub state: State,
    pub effective_priority: i32,
}

// 从所有状态中选出当前应激活的: 默认态兜底 + priority 最高 + 常驻压瞬态
pub fn select_active(
    states: &[State],
    m: &mut SystemMonitor,
    args: &Args,
    signals: &HashMap<String, Instant>,
) -> Option<ActiveState> {
    let mut best: Option<ActiveState> = None;
    for st in states {
        let hit = if st.is_default {
            true // 默认态永远参与
        } else {
            match &st.trigger {
                Some(t) => t.matches(m, args, signals),
                None => false,
            }
        };
        if !hit { continue; }
        // 常驻态优先级 +100，确保压过瞬态
        let eff = st.priority + if st.persistent { 100 } else { 0 };
        match &best {
            None => best = Some(ActiveState { state: st.clone(), effective_priority: eff }),
            Some(b) => if eff > b.effective_priority {
                best = Some(ActiveState { state: st.clone(), effective_priority: eff });
            },
        }
    }
    best
}
