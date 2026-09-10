use chrono::{DateTime, Local};
use serde_json::Value;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::UNIX_EPOCH;
use tzf_rs::DefaultFinder;

const GEOCLUE_WHERE_AM_I: &str = "/usr/lib/geoclue-2.0/demos/where-am-i";

#[derive(Clone, Debug, PartialEq)]
pub struct TimezoneUpdate {
    pub timezone: String,
    pub changed: bool,
    pub accuracy_km: u64,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HyprClient {
    pub pid: u32,
    pub workspace: i32,
    pub class: String,
    pub initial_class: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NotificationIdentifiers {
    pub pid: Option<u32>,
    pub desktop_entry: Option<String>,
    pub app: String,
}

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
    pub storage: u64,
    pub uptime: u64,
    pub brightness: u64,
    pub microphone_volume: u64,
    pub microphone_muted: bool,
    pub microphone_device: String,
    pub microphone_apps: Vec<String>,
    pub battery: u64,
    pub battery_status: String,
    pub profile: String,
    pub volume: u64,
    pub muted: bool,
    pub workspace: i32,
    pub workspace_apps: Vec<Vec<String>>,
    pub workspace_alerts: Vec<bool>,
    pub workspace_alert_pulses: Vec<bool>,
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

pub fn normalize_notification_identifier(value: &str) -> String {
    let value = value
        .trim()
        .trim_end_matches(".desktop")
        .rsplit('/')
        .next()
        .unwrap_or_default();
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

fn identifier_variants(value: &str) -> Vec<String> {
    let stripped = value.trim().trim_end_matches(".desktop");
    let mut values = vec![normalize_notification_identifier(stripped)];
    if let Some(last) = stripped.rsplit(['.', '/']).next() {
        values.push(normalize_notification_identifier(last));
    }
    values.retain(|value| !value.is_empty());
    values.sort();
    values.dedup();
    values
}

fn unique_workspace(matches: impl Iterator<Item = i32>) -> Option<i32> {
    let mut workspaces: Vec<i32> = matches.filter(|value| *value > 0).collect();
    workspaces.sort_unstable();
    workspaces.dedup();
    (workspaces.len() == 1).then(|| workspaces[0])
}

pub fn notification_workspace(
    identifiers: &NotificationIdentifiers,
    clients: &[HyprClient],
) -> Option<i32> {
    if let Some(pid) = identifiers.pid {
        let matches: Vec<_> = clients.iter().filter(|client| client.pid == pid).collect();
        if !matches.is_empty() {
            return unique_workspace(matches.into_iter().map(|client| client.workspace));
        }
    }
    for identifier in [identifiers.desktop_entry.as_deref(), Some(&identifiers.app)]
        .into_iter()
        .flatten()
    {
        let wanted = identifier_variants(identifier);
        if wanted.is_empty() {
            continue;
        }
        let matches: Vec<_> = clients
            .iter()
            .filter(|client| {
                [&client.class, &client.initial_class]
                    .into_iter()
                    .any(|class| {
                        let class = identifier_variants(class);
                        wanted.iter().any(|value| class.contains(value))
                    })
            })
            .collect();
        if !matches.is_empty() {
            return unique_workspace(matches.into_iter().map(|client| client.workspace));
        }
    }
    None
}

pub fn hypr_clients() -> Vec<HyprClient> {
    let Ok(clients) = serde_json::from_str::<Value>(&output("hyprctl", &["clients", "-j"])) else {
        return Vec::new();
    };
    clients
        .as_array()
        .into_iter()
        .flatten()
        .map(|client| HyprClient {
            pid: client["pid"].as_u64().unwrap_or_default() as u32,
            workspace: client["workspace"]["id"].as_i64().unwrap_or_default() as i32,
            class: client["class"].as_str().unwrap_or_default().to_string(),
            initial_class: client["initialClass"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
        })
        .filter(|client| client.workspace > 0)
        .collect()
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
    let mut command = Command::new(program);
    command.args(args);
    spawn_command(&mut command);
}

pub fn spawn_command(command: &mut Command) {
    let child = command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    if let Ok(mut child) = child {
        thread::spawn(move || {
            let _ = child.wait();
        });
    }
}

pub fn run(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
}

pub fn workspace_apps() -> Vec<Vec<String>> {
    let mut workspaces = vec![Vec::new(); 10];
    let Ok(clients) = serde_json::from_str::<Value>(&output("hyprctl", &["clients", "-j"])) else {
        return workspaces;
    };
    let Some(clients) = clients.as_array() else {
        return workspaces;
    };

    for client in clients {
        let workspace = client["workspace"]["id"].as_i64().unwrap_or_default();
        if !(1..=10).contains(&workspace) {
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

pub fn microphone() -> (u64, bool, String, Vec<String>) {
    let value = output("wpctl", &["get-volume", "@DEFAULT_AUDIO_SOURCE@"]);
    let volume = value
        .split_whitespace()
        .find_map(|part| part.parse::<f64>().ok())
        .map(|part| (part * 100.0).round() as u64)
        .unwrap_or(0)
        .min(100);
    let muted = value.contains("MUTED");
    let default_source = output("pactl", &["get-default-source"]);
    let sources =
        serde_json::from_str::<Value>(&output("pactl", &["-f", "json", "list", "sources"]))
            .ok()
            .and_then(|value| value.as_array().cloned())
            .unwrap_or_default();
    let device = sources
        .iter()
        .find(|source| source.get("name").and_then(Value::as_str) == Some(&default_source))
        .and_then(|source| source.get("description").and_then(Value::as_str))
        .unwrap_or(&default_source)
        .to_string();
    let raw = output("pactl", &["-f", "json", "list", "source-outputs"]);
    let apps = serde_json::from_str::<Value>(&raw)
        .ok()
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .filter_map(|stream| {
            let source_index = stream.get("source").and_then(Value::as_u64);
            let source_is_monitor = source_index
                .and_then(|index| {
                    sources
                        .iter()
                        .find(|source| source.get("index").and_then(Value::as_u64) == Some(index))
                })
                .is_some_and(|source| {
                    source
                        .get("name")
                        .and_then(Value::as_str)
                        .is_some_and(|name| name.ends_with(".monitor"))
                        || source
                            .get("monitor_of_sink")
                            .is_some_and(|value| !value.is_null())
                });
            let properties = stream.get("properties")?;
            let app = properties
                .get("application.name")
                .and_then(Value::as_str)
                .or_else(|| properties.get("media.name").and_then(Value::as_str))
                .unwrap_or_default();
            let node = properties
                .get("node.name")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let inspect = [app, node].join(" ").to_lowercase();
            (!source_is_monitor
                && !app.is_empty()
                && !inspect.contains("monitor")
                && !inspect.contains("nixie shell")
                && !inspect.contains("nixie-shell")
                && !inspect.contains("peak detect"))
            .then(|| app.to_string())
        })
        .fold(Vec::new(), |mut apps, app| {
            if !apps.contains(&app) {
                apps.push(app);
            }
            apps
        });
    (volume, muted, device, apps)
}

pub fn backlight_path() -> Option<PathBuf> {
    fs::read_dir("/sys/class/backlight")
        .ok()?
        .flatten()
        .map(|entry| entry.path().join("brightness"))
        .find(|path| path.exists())
}

pub fn brightness() -> u64 {
    let Some(path) = backlight_path() else {
        return 0;
    };
    let current = read(&path).parse::<u64>().unwrap_or(0);
    let maximum = read(path.with_file_name("max_brightness"))
        .parse::<u64>()
        .unwrap_or(0);
    if maximum == 0 {
        0
    } else {
        (100 * current / maximum).min(100)
    }
}

pub fn storage_percent() -> u64 {
    let path = std::ffi::CString::new("/").expect("root path");
    let mut stats = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    if unsafe { libc::statvfs(path.as_ptr(), stats.as_mut_ptr()) } != 0 {
        return 0;
    }
    let stats = unsafe { stats.assume_init() };
    if stats.f_blocks == 0 {
        return 0;
    }
    (100 * (stats.f_blocks.saturating_sub(stats.f_bavail)) / stats.f_blocks).min(100)
}

pub fn uptime_seconds() -> u64 {
    fs::read_to_string("/proc/uptime")
        .unwrap_or_default()
        .split_whitespace()
        .next()
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(0.0) as u64
}

pub fn current_timezone() -> String {
    let timezone = output("timedatectl", &["show", "--property=Timezone", "--value"]);
    if timezone.is_empty() {
        "Unknown".into()
    } else {
        timezone
    }
}

fn geoclue_value(text: &str, field: &str) -> Option<f64> {
    text.lines()
        .find_map(|line| line.trim().strip_prefix(field))
        .map(str::trim)
        .and_then(|value| {
            value
                .trim_end_matches(|character: char| !character.is_ascii_digit() && character != '.')
                .parse::<f64>()
                .ok()
        })
}

fn valid_timezone_name(timezone: &str) -> bool {
    !timezone.is_empty()
        && !timezone.starts_with('/')
        && !timezone.contains("..")
        && timezone.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '/' | '_' | '-' | '+')
        })
        && Path::new("/usr/share/zoneinfo").join(timezone).is_file()
}

pub fn detect_and_apply_timezone() -> Result<TimezoneUpdate, String> {
    let location = Command::new(GEOCLUE_WHERE_AM_I)
        .args(["--timeout=12", "--accuracy-level=4"])
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .output()
        .map_err(|_| "GeoClue location helper is unavailable".to_string())?;
    let location_text = String::from_utf8_lossy(&location.stdout);
    if !location.status.success() || location_text.trim().is_empty() {
        return Err("Could not determine location; check the network and location service".into());
    }
    let latitude = geoclue_value(&location_text, "Latitude:")
        .ok_or_else(|| "GeoClue returned no latitude".to_string())?;
    let longitude = geoclue_value(&location_text, "Longitude:")
        .ok_or_else(|| "GeoClue returned no longitude".to_string())?;
    let accuracy_km =
        (geoclue_value(&location_text, "Accuracy:").unwrap_or_default() / 1000.0).ceil() as u64;
    let finder = DefaultFinder::new();
    let timezone = finder.get_tz_name(longitude, latitude).to_string();
    if !valid_timezone_name(&timezone) {
        return Err("No time zone matched the detected location".into());
    }
    let changed = current_timezone() != timezone;
    if changed {
        let result = Command::new("timedatectl")
            .args(["set-timezone", &timezone])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
            .map_err(|_| "The system timezone service is unavailable".to_string())?;
        if !result.status.success() {
            let detail = String::from_utf8_lossy(&result.stderr).trim().to_string();
            return Err(if detail.is_empty() {
                "Authentication was cancelled; timezone was not changed".into()
            } else {
                format!("Could not change timezone: {detail}")
            });
        }
    }
    Ok(TimezoneUpdate {
        timezone,
        changed,
        accuracy_km,
    })
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

fn collect_jsonl(path: &Path, result: &mut Vec<(std::time::SystemTime, PathBuf)>) {
    let Ok(entries) = fs::read_dir(path) else {
        return;
    };
    for entry in entries.flatten() {
        let p = entry.path();
        if p.is_dir() {
            collect_jsonl(&p, result);
        } else if p.extension().and_then(|x| x.to_str()) == Some("jsonl") {
            if let Ok(modified) = entry.metadata().and_then(|metadata| metadata.modified()) {
                result.push((modified, p));
            }
        }
    }
}

fn recent_jsonl(path: &Path, limit: usize) -> Vec<PathBuf> {
    let mut files = Vec::new();
    collect_jsonl(path, &mut files);
    files.sort_unstable_by(|left, right| right.0.cmp(&left.0));
    files
        .into_iter()
        .take(limit)
        .map(|(_, path)| path)
        .collect()
}

fn quota_values_from_tail(data: &[u8]) -> Option<(String, i64, u64)> {
    let tail = String::from_utf8_lossy(data);
    for line in tail.lines().rev() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(rate_limits) = value
            .pointer("/payload/rate_limits")
            .or_else(|| value.get("rate_limits"))
        else {
            continue;
        };
        if rate_limits.get("limit_id").and_then(Value::as_str) != Some("codex") {
            continue;
        }
        let Some(used) = rate_limits
            .pointer("/primary/used_percent")
            .and_then(Value::as_f64)
        else {
            continue;
        };
        let remaining = (100.0 - used).round().clamp(0.0, 100.0) as i64;
        let resets_at = rate_limits
            .pointer("/primary/resets_at")
            .and_then(Value::as_u64)
            .unwrap_or(0);
        let timestamp = value
            .get("timestamp")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        return Some((timestamp, remaining, resets_at));
    }
    None
}

fn codex_quota() -> (i64, String) {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home/brine"));
    let mut newest = None;
    for path in recent_jsonl(&home.join(".codex/sessions"), 12) {
        let Ok(mut file) = File::open(path) else {
            continue;
        };
        let len = file.metadata().map(|metadata| metadata.len()).unwrap_or(0);
        let _ = file.seek(SeekFrom::Start(len.saturating_sub(1_000_000)));
        let mut tail = Vec::new();
        let _ = file.read_to_end(&mut tail);
        let Some(candidate) = quota_values_from_tail(&tail) else {
            continue;
        };
        if newest
            .as_ref()
            .is_none_or(|current: &(String, i64, u64)| candidate.0 > current.0)
        {
            newest = Some(candidate);
        }
    }
    let Some((_, remaining, resets_at)) = newest else {
        return (-1, "Unknown".into());
    };
    let reset = if resets_at == 0 {
        "Unknown".into()
    } else {
        DateTime::<Local>::from(UNIX_EPOCH + std::time::Duration::from_secs(resets_at))
            .format("%a %H:%M")
            .to_string()
    };
    (remaining, reset)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_latest_codex_quota_from_jsonl_tail() {
        let data = br#"{"timestamp":"2026-09-09T01:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":12.4,"resets_at":100}}}}
{"timestamp":"2026-09-09T02:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":51.0,"resets_at":200}}}}
"#;
        assert_eq!(
            quota_values_from_tail(data),
            Some(("2026-09-09T02:00:00Z".into(), 49, 200))
        );
    }

    #[test]
    fn quota_tail_tolerates_a_partial_multibyte_character() {
        let mut data = vec![0x80, 0x80, b'\n'];
        data.extend_from_slice(
            br#"{"timestamp":"2026-09-09T03:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":25.0,"resets_at":300}}}}
"#,
        );
        assert_eq!(
            quota_values_from_tail(&data),
            Some(("2026-09-09T03:00:00Z".into(), 75, 300))
        );
    }

    fn client(pid: u32, workspace: i32, class: &str) -> HyprClient {
        HyprClient {
            pid,
            workspace,
            class: class.into(),
            initial_class: String::new(),
        }
    }

    #[test]
    fn normalizes_notification_identifiers() {
        assert_eq!(
            normalize_notification_identifier(" org.mozilla.Firefox.desktop "),
            "orgmozillafirefox"
        );
        assert_eq!(
            normalize_notification_identifier("/usr/share/applications/discord.desktop"),
            "discord"
        );
    }

    #[test]
    fn pid_matching_has_priority() {
        let clients = vec![client(42, 3, "firefox"), client(7, 8, "discord")];
        let ids = NotificationIdentifiers {
            pid: Some(42),
            desktop_entry: Some("discord.desktop".into()),
            app: "Discord".into(),
        };
        assert_eq!(notification_workspace(&ids, &clients), Some(3));
    }

    #[test]
    fn matches_desktop_entry_and_application_class() {
        let clients = vec![client(1, 4, "firefox"), client(2, 7, "discord")];
        let firefox = NotificationIdentifiers {
            desktop_entry: Some("org.mozilla.firefox.desktop".into()),
            ..Default::default()
        };
        let discord = NotificationIdentifiers {
            app: "Discord".into(),
            ..Default::default()
        };
        assert_eq!(notification_workspace(&firefox, &clients), Some(4));
        assert_eq!(notification_workspace(&discord, &clients), Some(7));
    }

    #[test]
    fn ambiguous_and_unmatched_notifications_are_unassigned() {
        let clients = vec![client(1, 2, "firefox"), client(2, 5, "firefox")];
        let firefox = NotificationIdentifiers {
            app: "Firefox".into(),
            ..Default::default()
        };
        let unknown = NotificationIdentifiers {
            app: "Unknown".into(),
            ..Default::default()
        };
        assert_eq!(notification_workspace(&firefox, &clients), None);
        assert_eq!(notification_workspace(&unknown, &clients), None);
    }

    #[test]
    fn parses_geoclue_coordinates() {
        let response =
            "Latitude:    35.600000°\nLongitude:   139.317000°\nAccuracy:    25000 meters\n";
        assert_eq!(geoclue_value(response, "Latitude:"), Some(35.6));
        assert_eq!(geoclue_value(response, "Longitude:"), Some(139.317));
        assert_eq!(geoclue_value(response, "Accuracy:"), Some(25000.0));
    }

    #[test]
    fn rejects_unsafe_timezone_names() {
        assert!(valid_timezone_name("Asia/Tokyo"));
        assert!(!valid_timezone_name("../../etc/passwd"));
        assert!(!valid_timezone_name("Asia/Tokyo; reboot"));
    }

    #[test]
    fn maps_detected_coordinates_to_timezone() {
        let finder = DefaultFinder::new();
        assert_eq!(finder.get_tz_name(139.317, 35.6), "Asia/Tokyo");
        assert_eq!(finder.get_tz_name(121.5654, 25.033), "Asia/Taipei");
    }
}
