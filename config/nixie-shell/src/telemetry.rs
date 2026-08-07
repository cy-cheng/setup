use chrono::{DateTime, Local};
use serde_json::Value;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::UNIX_EPOCH;

#[derive(Clone, Default)]
pub struct CpuSample { pub idle: u64, pub total: u64 }

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
}

#[derive(Clone, Debug, Default)]
pub struct HistoryItem {
    pub id: u64,
    pub app: String,
    pub summary: String,
    pub body: String,
}

pub fn output(program: &str, args: &[&str]) -> String {
    Command::new(program).args(args).stdout(Stdio::piped()).stderr(Stdio::null())
        .output().ok().filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default()
}

pub fn spawn(program: &str, args: &[&str]) {
    let _ = Command::new(program).args(args).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
}

pub fn read(path: impl AsRef<Path>) -> String {
    fs::read_to_string(path).unwrap_or_default().trim().to_string()
}

pub fn cpu_sample() -> CpuSample {
    let values: Vec<u64> = fs::read_to_string("/proc/stat").unwrap_or_default().lines().next()
        .unwrap_or_default().split_whitespace().skip(1).filter_map(|v| v.parse().ok()).collect();
    CpuSample { idle: values.get(3).copied().unwrap_or(0) + values.get(4).copied().unwrap_or(0), total: values.iter().sum() }
}

pub fn cpu_percent(old: &CpuSample, new: &CpuSample) -> u64 {
    let total = new.total.saturating_sub(old.total);
    let idle = new.idle.saturating_sub(old.idle);
    if total == 0 { 0 } else { (100 * total.saturating_sub(idle) / total).min(100) }
}

fn memory_percent() -> u64 {
    let mut total = 0u64;
    let mut available = 0u64;
    for line in fs::read_to_string("/proc/meminfo").unwrap_or_default().lines() {
        let mut fields = line.split_whitespace();
        match fields.next() {
            Some("MemTotal:") => total = fields.next().and_then(|v| v.parse().ok()).unwrap_or(0),
            Some("MemAvailable:") => available = fields.next().and_then(|v| v.parse().ok()).unwrap_or(0),
            _ => {}
        }
    }
    if total == 0 { 0 } else { 100 * total.saturating_sub(available) / total }
}

fn temperature() -> i64 {
    for base in ["/sys/class/hwmon", "/sys/class/thermal"] {
        if let Ok(entries) = fs::read_dir(base) {
            for entry in entries.flatten() {
                for name in ["temp1_input", "temp2_input", "temp"] {
                    let value = read(entry.path().join(name)).parse::<i64>().unwrap_or(0);
                    if value > 0 { return if value > 1000 { value / 1000 } else { value }; }
                }
            }
        }
    }
    0
}

fn active_workspace() -> i32 {
    output("hyprctl", &["activeworkspace", "-j"]).split("\"id\"").nth(1)
        .and_then(|s| s.split(':').nth(1)).and_then(|s| s.trim().split([',', '}']).next())
        .and_then(|s| s.parse().ok()).unwrap_or(1)
}

fn audio() -> (u64, bool) {
    let value = output("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"]) ;
    let volume = value.split_whitespace().find_map(|v| v.parse::<f64>().ok())
        .map(|v| (v * 100.0).round() as u64).unwrap_or(0).min(100);
    (volume, value.contains("MUTED"))
}

fn network() -> (String, String, String) {
    let status = output("nmcli", &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]);
    let active = status.lines().find(|l| l.contains(":connected:") && !l.contains(":loopback:"));
    let Some(line) = active else { return ("Disconnected".into(), "󰖪".into(), "Network disconnected".into()); };
    let fields: Vec<&str> = line.split(':').collect();
    let iface = fields.first().copied().unwrap_or("");
    let kind = fields.get(1).copied().unwrap_or("");
    let name = fields.get(3..).unwrap_or(&[]).join(":");
    let ip = output("nmcli", &["-g", "IP4.ADDRESS", "device", "show", iface]).lines().next().unwrap_or("").to_string();
    let mut signal = String::new();
    let icon = if kind == "wifi" {
        signal = output("nmcli", &["-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list"])
            .lines().find(|l| l.starts_with('*')).and_then(|l| l.split(':').nth(1)).unwrap_or("").to_string();
        match signal.parse::<u64>().unwrap_or(0) { 75.. => "󰤨", 50..=74 => "󰤥", 25..=49 => "󰤢", _ => "󰤟" }
    } else { "󰈀" };
    let vpns: Vec<String> = output("nmcli", &["-t", "-f", "TYPE,NAME", "connection", "show", "--active"])
        .lines().filter(|l| l.starts_with("vpn:") || l.starts_with("wireguard:")).filter_map(|l| l.split_once(':').map(|x| x.1.to_string())).collect();
    let tip = format!("{}: {}\n{}{}\nInterface: {}\nIPv4: {}{}", if kind == "wifi" { "Wi-Fi" } else { "Ethernet" }, name,
        if signal.is_empty() { "" } else { "Signal: " }, if signal.is_empty() { "".into() } else { format!("{}%", signal) }, iface, ip,
        if vpns.is_empty() { "".into() } else { format!("\nVPN: {}", vpns.join(", ")) });
    (name, icon.into(), tip)
}

fn bluetooth() -> (bool, Vec<String>) {
    let show = output("bluetoothctl", &["show"]);
    let powered = show.lines().any(|l| l.trim() == "Powered: yes");
    let names = output("bluetoothctl", &["devices", "Connected"]).lines().filter_map(|line| {
        let mut p = line.splitn(3, ' '); let _ = p.next(); let _ = p.next(); p.next().map(str::to_string)
    }).collect();
    (powered, names)
}

fn active_llms() -> u64 {
    fs::read_dir("/proc").ok().into_iter().flatten().flatten().filter(|e| {
        let comm = read(e.path().join("comm")).to_lowercase();
        matches!(comm.as_str(), "codex" | "claude" | "gemini" | "opencode")
    }).count() as u64
}

fn latest_jsonl(path: &Path) -> Option<PathBuf> {
    let mut result = None;
    for entry in fs::read_dir(path).ok()?.flatten() {
        let p = entry.path();
        if p.is_dir() {
            if let Some(child) = latest_jsonl(&p) {
                let t = fs::metadata(&child).ok()?.modified().ok()?;
                if result.as_ref().is_none_or(|(old, _)| t > *old) { result = Some((t, child)); }
            }
        } else if p.extension().and_then(|x| x.to_str()) == Some("jsonl") {
            let t = entry.metadata().ok()?.modified().ok()?;
            if result.as_ref().is_none_or(|(old, _)| t > *old) { result = Some((t, p)); }
        }
    }
    result.map(|x| x.1)
}

fn number_after(data: &str, key: &str) -> Option<f64> {
    let tail = &data[data.find(key)? + key.len()..];
    let value = tail[tail.find(':')? + 1..].trim_start();
    let n = value.chars().take_while(|c| c.is_ascii_digit() || *c == '.' || *c == '-').count();
    value.get(..n)?.parse().ok()
}

fn codex_quota() -> (i64, String) {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home/brine"));
    let Some(path) = latest_jsonl(&home.join(".codex/sessions")) else { return (-1, "Unknown".into()); };
    let Ok(mut f) = File::open(path) else { return (-1, "Unknown".into()); };
    let len = f.metadata().map(|m| m.len()).unwrap_or(0); let _ = f.seek(SeekFrom::Start(len.saturating_sub(2_000_000)));
    let mut tail = String::new(); let _ = f.read_to_string(&mut tail);
    for line in tail.lines().rev() {
        let Some(pos) = line.find("\"limit_id\":\"codex\"") else { continue };
        let q = &line[pos..]; let Some(used) = number_after(q, "\"used_percent\"") else { continue };
        let remaining = (100.0 - used).round().clamp(0.0, 100.0) as i64;
        let reset = number_after(q, "\"resets_at\"").map(|v| DateTime::<Local>::from(UNIX_EPOCH + std::time::Duration::from_secs(v as u64)).format("%a %H:%M").to_string()).unwrap_or_else(|| "Unknown".into());
        return (remaining, reset);
    }
    (-1, "Unknown".into())
}

pub fn collect(previous: &CpuSample, include_services: bool, include_llm: bool, old: &Snapshot) -> (Snapshot, CpuSample) {
    let now = cpu_sample(); let (volume, muted) = audio();
    let mut snap = old.clone();
    snap.cpu = cpu_percent(previous, &now); snap.mem = memory_percent(); snap.temp = temperature();
    snap.battery = read("/sys/class/power_supply/BAT0/capacity").parse().unwrap_or(0);
    snap.battery_status = read("/sys/class/power_supply/BAT0/status");
    snap.profile = match read("/sys/firmware/acpi/platform_profile").as_str() { "quiet" | "low-power" => "power-saver".into(), "performance" => "performance".into(), "" => "balanced".into(), x => x.into() };
    snap.volume = volume; snap.muted = muted; snap.workspace = active_workspace();
    if include_services {
        let (name, icon, tip) = network(); snap.network_name = name; snap.network_icon = icon; snap.network_tooltip = tip;
        let (powered, names) = bluetooth(); snap.bluetooth_powered = powered; snap.bluetooth_count = names.len(); snap.bluetooth_names = names;
        snap.notifications = output("dunstctl", &["count", "history"]).parse().unwrap_or(0);
        snap.dnd = output("dunstctl", &["is-paused"]) == "true";
    }
    if include_llm { let (left, reset) = codex_quota(); snap.codex_remaining = left; snap.codex_reset = reset; snap.active_llms = active_llms(); }
    (snap, now)
}

fn field_text(value: &Value) -> String {
    if let Some(s) = value.as_str() { return s.to_string(); }
    if let Some(data) = value.get("data").and_then(Value::as_str) { return data.to_string(); }
    if let Some(s) = value.get("value").and_then(Value::as_str) { return s.to_string(); }
    String::new()
}

pub fn history() -> Vec<HistoryItem> {
    let raw = output("dunstctl", &["history"]); let Ok(root) = serde_json::from_str::<Value>(&raw) else { return vec![] };
    let arrays = root.get("data").and_then(Value::as_array).or_else(|| root.as_array());
    let Some(groups) = arrays else { return vec![] };
    let mut out = Vec::new();
    for group in groups {
        let entries = group.as_array().map(Vec::as_slice).unwrap_or(&[]);
        for item in entries {
            out.push(HistoryItem {
                id: item.get("id").and_then(|v| v.get("data")).and_then(Value::as_u64).or_else(|| item.get("id").and_then(Value::as_u64)).unwrap_or(0),
                app: item.get("appname").map(field_text).unwrap_or_default(),
                summary: item.get("summary").map(field_text).unwrap_or_default(),
                body: item.get("body").map(field_text).unwrap_or_default(),
            });
        }
    }
    out
}
