use chrono::{DateTime, Local};
use serde_json::Value;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::UNIX_EPOCH;

#[derive(Clone, Default)]
pub struct CpuSample {
    pub idle: u64,
    pub total: u64,
}

#[derive(Clone, Default)]
pub struct Snapshot {
    pub cpu: u64,
    pub mem: u64,
    pub temp: i64,
    pub battery: u64,
    pub battery_status: String,
    pub profile: String,
    pub volume: u64,
    pub muted: bool,
    pub workspace: i32,
    pub workspace_apps: Vec<Vec<String>>,
    pub network_name: String,
    pub network_icon: String,
    pub network_tooltip: String,
    pub bluetooth_count: usize,
    pub bluetooth_names: Vec<String>,
    pub bluetooth_powered: bool,
    pub notifications: u64,
    pub dnd: bool,
    pub codex_remaining: i64,
    pub codex_reset: String,
    pub codex_today: u64,
    pub active_llms: u64,
    pub idle_inhibited: bool,
}

#[derive(Clone, Debug, Default)]
pub struct HistoryItem {
    pub id: u64,
    pub app: String,
    pub summary: String,
    pub body: String,
}

pub fn output(program: &str, args: &[&str]) -> String {
    Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

pub fn spawn(program: &str, args: &[&str]) {
    let _ = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

pub fn workspace_apps() -> Vec<Vec<String>> {
    let mut workspaces = vec![Vec::new(); 4];
    let Ok(clients) = serde_json::from_str::<Value>(&output("hyprctl", &["clients", "-j"])) else {
        return workspaces;
    };
    let Some(clients) = clients.as_array() else {
        return workspaces;
    };

    for client in clients {
        let workspace = client["workspace"]["id"].as_i64().unwrap_or_default();
        if !(1..=4).contains(&workspace) {
            continue;
        }
        let class = client["class"]
            .as_str()
            .filter(|value| !value.is_empty())
            .or_else(|| client["initialClass"].as_str())
            .unwrap_or_default()
            .to_lowercase();
        let apps = &mut workspaces[(workspace - 1) as usize];
        if !class.is_empty() && !apps.contains(&class) {
            apps.push(class);
        }
    }
    workspaces
}

pub fn read(path: impl AsRef<Path>) -> String {
    fs::read_to_string(path)
        .unwrap_or_default()
        .trim()
        .to_string()
}

pub fn cpu_sample() -> CpuSample {
    let values: Vec<u64> = fs::read_to_string("/proc/stat")
        .unwrap_or_default()
        .lines()
        .next()
        .unwrap_or_default()
        .split_whitespace()
        .skip(1)
        .filter_map(|v| v.parse().ok())
        .collect();
    CpuSample {
        idle: values.get(3).copied().unwrap_or(0) + values.get(4).copied().unwrap_or(0),
        total: values.iter().sum(),
    }
}

pub fn cpu_percent(old: &CpuSample, new: &CpuSample) -> u64 {
    let total = new.total.saturating_sub(old.total);
    let idle = new.idle.saturating_sub(old.idle);
    if total == 0 {
        0
    } else {
        (100 * total.saturating_sub(idle) / total).min(100)
    }
}

fn memory_percent() -> u64 {
    let mut total = 0u64;
    let mut available = 0u64;
    for line in fs::read_to_string("/proc/meminfo")
        .unwrap_or_default()
        .lines()
    {
        let mut fields = line.split_whitespace();
        match fields.next() {
            Some("MemTotal:") => total = fields.next().and_then(|v| v.parse().ok()).unwrap_or(0),
            Some("MemAvailable:") => {
                available = fields.next().and_then(|v| v.parse().ok()).unwrap_or(0)
            }
            _ => {}
        }
    }
    if total == 0 {
        0
    } else {
        100 * total.saturating_sub(available) / total
    }
}

fn temperature() -> i64 {
    for base in ["/sys/class/hwmon", "/sys/class/thermal"] {
        if let Ok(entries) = fs::read_dir(base) {
            for entry in entries.flatten() {
                for name in ["temp1_input", "temp2_input", "temp"] {
                    let value = read(entry.path().join(name)).parse::<i64>().unwrap_or(0);
                    if value > 0 {
                        return if value > 1000 { value / 1000 } else { value };
                    }
                }
            }
        }
    }
    0
}

pub fn active_workspace() -> i32 {
    output("hyprctl", &["activeworkspace", "-j"])
        .split("\"id\"")
        .nth(1)
        .and_then(|s| s.split(':').nth(1))
        .and_then(|s| s.trim().split([',', '}']).next())
        .and_then(|s| s.parse().ok())
        .unwrap_or(1)
}

pub fn audio() -> (u64, bool) {
    let value = output("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"]);
    let volume = value
        .split_whitespace()
        .find_map(|v| v.parse::<f64>().ok())
        .map(|v| (v * 100.0).round() as u64)
        .unwrap_or(0)
        .min(100);
    (volume, value.contains("MUTED"))
}

pub fn network() -> (String, String, String) {
    let status = output(
        "nmcli",
        &[
            "-t",
            "-f",
            "DEVICE,TYPE,STATE,CONNECTION",
            "device",
            "status",
        ],
    );
    let active = status
        .lines()
        .find(|l| l.contains(":connected:") && !l.contains(":loopback:"));
    let Some(line) = active else {
        return (
            "Disconnected".into(),
            "󰖪".into(),
            "Network disconnected".into(),
        );
    };
    let fields: Vec<&str> = line.split(':').collect();
    let iface = fields.first().copied().unwrap_or("");
    let kind = fields.get(1).copied().unwrap_or("");
    let name = fields.get(3..).unwrap_or(&[]).join(":");
    let ip = output("nmcli", &["-g", "IP4.ADDRESS", "device", "show", iface])
        .lines()
        .next()
        .unwrap_or("")
        .to_string();
    let mut signal = String::new();
    let icon = if kind == "wifi" {
        signal = output(
            "nmcli",
            &["-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list"],
        )
        .lines()
        .find(|l| l.starts_with('*'))
        .and_then(|l| l.split(':').nth(1))
        .unwrap_or("")
        .to_string();
        match signal.parse::<u64>().unwrap_or(0) {
            75.. => "󰤨",
            50..=74 => "󰤥",
            25..=49 => "󰤢",
            _ => "󰤟",
        }
    } else {
        "󰈀"
    };
    let vpns: Vec<String> = output(
        "nmcli",
        &["-t", "-f", "TYPE,NAME", "connection", "show", "--active"],
    )
    .lines()
    .filter(|l| l.starts_with("vpn:") || l.starts_with("wireguard:"))
    .filter_map(|l| l.split_once(':').map(|x| x.1.to_string()))
    .collect();
    let tip = format!(
        "{}: {}\n{}{}\nInterface: {}\nIPv4: {}{}",
        if kind == "wifi" { "Wi-Fi" } else { "Ethernet" },
        name,
        if signal.is_empty() { "" } else { "Signal: " },
        if signal.is_empty() {
            "".into()
        } else {
            format!("{}%", signal)
        },
        iface,
        ip,
        if vpns.is_empty() {
            "".into()
        } else {
            format!("\nVPN: {}", vpns.join(", "))
        }
    );
    (name, icon.into(), tip)
}

pub fn bluetooth() -> (bool, Vec<String>) {
    let show = output("bluetoothctl", &["show"]);
    let powered = show.lines().any(|l| l.trim() == "Powered: yes");
    let names = output("bluetoothctl", &["devices", "Connected"])
        .lines()
        .filter_map(|line| {
            let mut p = line.splitn(3, ' ');
            let _ = p.next();
            let _ = p.next();
            p.next().map(str::to_string)
        })
        .collect();
    (powered, names)
}

fn active_llms() -> u64 {
    fs::read_dir("/proc")
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| {
            let comm = read(e.path().join("comm")).to_lowercase();
            matches!(comm.as_str(), "codex" | "claude" | "gemini" | "opencode")
        })
        .count() as u64
}

fn latest_jsonl(path: &Path) -> Option<PathBuf> {
    let mut result = None;
    for entry in fs::read_dir(path).ok()?.flatten() {
        let p = entry.path();
        if p.is_dir() {
            if let Some(child) = latest_jsonl(&p) {
                let t = fs::metadata(&child).ok()?.modified().ok()?;
                if result.as_ref().is_none_or(|(old, _)| t > *old) {
                    result = Some((t, child));
                }
            }
        } else if p.extension().and_then(|x| x.to_str()) == Some("jsonl") {
            let t = entry.metadata().ok()?.modified().ok()?;
            if result.as_ref().is_none_or(|(old, _)| t > *old) {
                result = Some((t, p));
            }
        }
    }
    result.map(|x| x.1)
}

fn number_after(data: &str, key: &str) -> Option<f64> {
    let tail = &data[data.find(key)? + key.len()..];
    let value = tail[tail.find(':')? + 1..].trim_start();
    let n = value
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.' || *c == '-')
        .count();
    value.get(..n)?.parse().ok()
}

fn codex_quota() -> (i64, String) {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home/brine"));
    let Some(path) = latest_jsonl(&home.join(".codex/sessions")) else {
        return (-1, "Unknown".into());
    };
    let Ok(mut f) = File::open(path) else {
        return (-1, "Unknown".into());
    };
    let len = f.metadata().map(|m| m.len()).unwrap_or(0);
    let _ = f.seek(SeekFrom::Start(len.saturating_sub(2_000_000)));
    let mut tail = String::new();
    let _ = f.read_to_string(&mut tail);
    for line in tail.lines().rev() {
        let Some(pos) = line.find("\"limit_id\":\"codex\"") else {
            continue;
        };
        let q = &line[pos..];
        let Some(used) = number_after(q, "\"used_percent\"") else {
            continue;
        };
        let remaining = (100.0 - used).round().clamp(0.0, 100.0) as i64;
        let reset = number_after(q, "\"resets_at\"")
            .map(|v| {
                DateTime::<Local>::from(UNIX_EPOCH + std::time::Duration::from_secs(v as u64))
                    .format("%a %H:%M")
                    .to_string()
            })
            .unwrap_or_else(|| "Unknown".into());
        return (remaining, reset);
    }
    (-1, "Unknown".into())
}

pub fn metrics(previous: &CpuSample) -> (u64, u64, i64, CpuSample) {
    let now = cpu_sample();
    (
        cpu_percent(previous, &now),
        memory_percent(),
        temperature(),
        now,
    )
}

pub fn battery() -> (u64, String) {
    (
        read("/sys/class/power_supply/BAT0/capacity")
            .parse()
            .unwrap_or(0),
        read("/sys/class/power_supply/BAT0/status"),
    )
}

pub fn notification_state() -> (u64, bool) {
    (
        output("dunstctl", &["count", "history"])
            .parse()
            .unwrap_or(0),
        output("dunstctl", &["is-paused"]) == "true",
    )
}

pub fn llm() -> (i64, String, u64) {
    let (remaining, reset) = codex_quota();
    (remaining, reset, active_llms())
}

pub fn idle_inhibited() -> bool {
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::geteuid() }));
    Path::new(&runtime).join("nixie-idle-inhibited").exists()
}

fn field_text(value: &Value) -> String {
    if let Some(s) = value.as_str() {
        return s.to_string();
    }
    if let Some(data) = value.get("data").and_then(Value::as_str) {
        return data.to_string();
    }
    if let Some(s) = value.get("value").and_then(Value::as_str) {
        return s.to_string();
    }
    String::new()
}

pub fn history() -> Vec<HistoryItem> {
    let raw = output("dunstctl", &["history"]);
    let Ok(root) = serde_json::from_str::<Value>(&raw) else {
        return vec![];
    };
    let arrays = root
        .get("data")
        .and_then(Value::as_array)
        .or_else(|| root.as_array());
    let Some(groups) = arrays else { return vec![] };
    let mut out = Vec::new();
    for group in groups {
        let entries = group.as_array().map(Vec::as_slice).unwrap_or(&[]);
        for item in entries {
            out.push(HistoryItem {
                id: item
                    .get("id")
                    .and_then(|v| v.get("data"))
                    .and_then(Value::as_u64)
                    .or_else(|| item.get("id").and_then(Value::as_u64))
                    .unwrap_or(0),
                app: item.get("appname").map(field_text).unwrap_or_default(),
                summary: item.get("summary").map(field_text).unwrap_or_default(),
                body: item.get("body").map(field_text).unwrap_or_default(),
            });
        }
    }
    out
}
