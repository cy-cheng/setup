use crate::telemetry::{self, Snapshot};
use futures::{FutureExt, StreamExt, TryStreamExt};
use glib::Sender;
use libpulse_binding as pulse;
use pulse::context::{subscribe::InterestMaskSet, Context, FlagSet, State};
use pulse::mainloop::standard::{IterateResult, Mainloop};
use std::ffi::CString;
use std::io::{BufRead, BufReader};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};
use zbus::{MatchRule, MessageStream, MessageType, Proxy};

#[derive(Clone)]
pub enum ModuleUpdate {
    Workspace(i32),
    WorkspaceApps(Vec<Vec<String>>),
    Metrics {
        cpu: u64,
        mem: u64,
        temp: i64,
    },
    ExtendedSystem {
        storage: u64,
        uptime: u64,
    },
    Brightness(u64),
    Microphone {
        volume: u64,
        muted: bool,
        device: String,
        apps: Vec<String>,
    },
    WorkspaceAlert {
        workspace: i32,
        active: bool,
    },
    WorkspaceAlertPulse {
        workspace: i32,
        active: bool,
    },
    ClearWorkspaceAlerts,
    Audio {
        volume: u64,
        muted: bool,
    },
    Battery {
        percent: u64,
        status: String,
    },
    Profile(String),
    Network {
        name: String,
        icon: String,
        tooltip: String,
    },
    Bluetooth {
        powered: bool,
        names: Vec<String>,
    },
    Notifications {
        count: u64,
        dnd: bool,
    },
    Llm {
        remaining: i64,
        reset: String,
        active: u64,
    },
    Idle(bool),
    TimezoneChanged,
}

impl ModuleUpdate {
    pub fn apply(self, state: &mut Snapshot) {
        match self {
            Self::Workspace(value) => state.workspace = value,
            Self::WorkspaceApps(value) => state.workspace_apps = value,
            Self::Metrics { cpu, mem, temp } => {
                state.cpu = cpu;
                state.mem = mem;
                state.temp = temp;
            }
            Self::ExtendedSystem { storage, uptime } => {
                state.storage = storage;
                state.uptime = uptime;
            }
            Self::Brightness(value) => state.brightness = value,
            Self::Microphone {
                volume,
                muted,
                device,
                apps,
            } => {
                state.microphone_volume = volume;
                state.microphone_muted = muted;
                state.microphone_device = device;
                state.microphone_apps = apps;
            }
            Self::WorkspaceAlert { workspace, active } => {
                if state.workspace_alerts.len() < 10 {
                    state.workspace_alerts.resize(10, false);
                }
                if state.workspace_alert_pulses.len() < 10 {
                    state.workspace_alert_pulses.resize(10, false);
                }
                if let Some(alert) = state
                    .workspace_alerts
                    .get_mut((workspace - 1).max(0) as usize)
                {
                    *alert = active;
                }
                if let Some(pulse) = state
                    .workspace_alert_pulses
                    .get_mut((workspace - 1).max(0) as usize)
                {
                    *pulse = active;
                }
            }
            Self::WorkspaceAlertPulse { workspace, active } => {
                if state.workspace_alert_pulses.len() < 10 {
                    state.workspace_alert_pulses.resize(10, false);
                }
                if let Some(pulse) = state
                    .workspace_alert_pulses
                    .get_mut((workspace - 1).max(0) as usize)
                {
                    *pulse = active;
                }
            }
            Self::ClearWorkspaceAlerts => {
                state.workspace_alerts.resize(10, false);
                state.workspace_alerts.fill(false);
                state.workspace_alert_pulses.resize(10, false);
                state.workspace_alert_pulses.fill(false);
            }
            Self::Audio { volume, muted } => {
                state.volume = volume;
                state.muted = muted;
            }
            Self::Battery { percent, status } => {
                state.battery = percent;
                state.battery_status = status;
            }
            Self::Profile(value) => state.profile = value,
            Self::Network {
                name,
                icon,
                tooltip,
            } => {
                state.network_name = name;
                state.network_icon = icon;
                state.network_tooltip = tooltip;
            }
            Self::Bluetooth { powered, names } => {
                state.bluetooth_powered = powered;
                state.bluetooth_count = names.len();
                state.bluetooth_names = names;
            }
            Self::Notifications { count, dnd } => {
                state.notifications = count;
                state.dnd = dnd;
            }
            Self::Llm {
                remaining,
                reset,
                active,
            } => {
                state.codex_remaining = remaining;
                state.codex_reset = reset;
                state.active_llms = active;
            }
            Self::Idle(value) => state.idle_inhibited = value,
            Self::TimezoneChanged => {}
        }
    }
}

fn send_audio(tx: &Sender<ModuleUpdate>) {
    let (volume, muted) = telemetry::audio();
    let _ = tx.send(ModuleUpdate::Audio { volume, muted });
}

fn send_microphone(tx: &Sender<ModuleUpdate>) {
    let (volume, muted, device, apps) = telemetry::microphone();
    let _ = tx.send(ModuleUpdate::Microphone {
        volume,
        muted,
        device,
        apps,
    });
}

pub fn refresh_extended_system(tx: &Sender<ModuleUpdate>) {
    let _ = tx.send(ModuleUpdate::ExtendedSystem {
        storage: telemetry::storage_percent(),
        uptime: telemetry::uptime_seconds(),
    });
}

fn send_network(tx: &Sender<ModuleUpdate>) {
    let (name, icon, tooltip) = telemetry::network();
    let _ = tx.send(ModuleUpdate::Network {
        name,
        icon,
        tooltip,
    });
}

fn send_bluetooth(tx: &Sender<ModuleUpdate>) {
    let (powered, names) = telemetry::bluetooth();
    let _ = tx.send(ModuleUpdate::Bluetooth { powered, names });
}

pub fn refresh_notifications(tx: &Sender<ModuleUpdate>) {
    let (count, dnd) = telemetry::notification_state();
    let _ = tx.send(ModuleUpdate::Notifications { count, dnd });
}

pub fn start_workspace(tx: Sender<ModuleUpdate>) {
    thread::spawn(move || loop {
        let _ = tx.send(ModuleUpdate::Workspace(telemetry::active_workspace()));
        let _ = tx.send(ModuleUpdate::WorkspaceApps(telemetry::workspace_apps()));
        let runtime = std::env::var("XDG_RUNTIME_DIR")
            .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::geteuid() }));
        let signature = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
        let path = PathBuf::from(runtime)
            .join("hypr")
            .join(signature)
            .join(".socket2.sock");
        match UnixStream::connect(path) {
            Ok(stream) => {
                for line in BufReader::new(stream).lines().map_while(Result::ok) {
                    let value = line
                        .strip_prefix("workspace>>")
                        .and_then(|v| v.split(',').next())
                        .or_else(|| {
                            line.strip_prefix("focusedmon>>")
                                .and_then(|v| v.rsplit(',').next())
                        });
                    if let Some(workspace) = value.and_then(|v| v.parse::<i32>().ok()) {
                        if tx.send(ModuleUpdate::Workspace(workspace)).is_err() {
                            return;
                        }
                    }
                    if (line.starts_with("openwindow>>")
                        || line.starts_with("closewindow>>")
                        || line.starts_with("movewindow>>"))
                        && tx
                            .send(ModuleUpdate::WorkspaceApps(telemetry::workspace_apps()))
                            .is_err()
                    {
                        return;
                    }
                }
            }
            Err(error) => log::warn!("Hyprland event socket: {error}"),
        }
        thread::sleep(Duration::from_millis(500));
    });
}

pub fn start_audio(tx: Sender<ModuleUpdate>) {
    thread::spawn(move || loop {
        let Some(mut mainloop) = Mainloop::new() else {
            return;
        };
        let Some(mut context) = Context::new(&mainloop, "Nixie Shell") else {
            return;
        };
        if let Err(error) = context.connect(None, FlagSet::NOFLAGS, None) {
            log::warn!("PulseAudio connect: {error}");
            thread::sleep(Duration::from_secs(1));
            continue;
        }
        loop {
            match context.get_state() {
                State::Ready => break,
                State::Failed | State::Terminated => break,
                _ => {
                    if !matches!(mainloop.iterate(true), IterateResult::Success(_)) {
                        break;
                    }
                }
            }
        }
        if context.get_state() != State::Ready {
            thread::sleep(Duration::from_secs(1));
            continue;
        }
        send_audio(&tx);
        send_microphone(&tx);
        let event_tx = tx.clone();
        context.set_subscribe_callback(Some(Box::new(move |facility, _, _| {
            if matches!(
                facility,
                Some(
                    pulse::context::subscribe::Facility::Sink
                        | pulse::context::subscribe::Facility::Source
                        | pulse::context::subscribe::Facility::SourceOutput
                        | pulse::context::subscribe::Facility::Server
                )
            ) {
                send_audio(&event_tx);
                send_microphone(&event_tx);
            }
        })));
        let _subscription = context.subscribe(
            InterestMaskSet::SINK
                | InterestMaskSet::SOURCE
                | InterestMaskSet::SOURCE_OUTPUT
                | InterestMaskSet::SERVER,
            |_| {},
        );
        if let Err((error, _)) = mainloop.run() {
            log::warn!("PulseAudio event loop: {error}");
        }
        thread::sleep(Duration::from_secs(1));
    });
}

pub fn start_brightness(tx: Sender<ModuleUpdate>) {
    thread::spawn(move || {
        let Some(path) = telemetry::backlight_path() else {
            return;
        };
        let _ = tx.send(ModuleUpdate::Brightness(telemetry::brightness()));
        let descriptor = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
        if descriptor < 0 {
            return;
        }
        let Ok(path) = CString::new(path.to_string_lossy().as_bytes()) else {
            unsafe { libc::close(descriptor) };
            return;
        };
        let watch = unsafe {
            libc::inotify_add_watch(
                descriptor,
                path.as_ptr(),
                libc::IN_MODIFY | libc::IN_CLOSE_WRITE,
            )
        };
        if watch < 0 {
            unsafe { libc::close(descriptor) };
            return;
        }
        let mut buffer = [0u8; 512];
        loop {
            let read = unsafe { libc::read(descriptor, buffer.as_mut_ptr().cast(), buffer.len()) };
            if read <= 0
                || tx
                    .send(ModuleUpdate::Brightness(telemetry::brightness()))
                    .is_err()
            {
                break;
            }
        }
        unsafe { libc::close(descriptor) };
    });
}

pub fn start_metrics(tx: Sender<ModuleUpdate>, metrics_seconds: u64) {
    thread::spawn(move || {
        let mut sample = telemetry::cpu_sample();
        loop {
            thread::sleep(Duration::from_secs(metrics_seconds.max(1)));
            let (cpu, mem, temp, next) = telemetry::metrics(&sample);
            sample = next;
            if tx.send(ModuleUpdate::Metrics { cpu, mem, temp }).is_err() {
                return;
            }
        }
    });
}

pub fn start_llm(tx: Sender<ModuleUpdate>, llm_seconds: u64) {
    thread::spawn(move || loop {
        let (remaining, reset, active) = telemetry::llm();
        if tx
            .send(ModuleUpdate::Llm {
                remaining,
                reset,
                active,
            })
            .is_err()
        {
            return;
        }
        thread::sleep(Duration::from_secs(llm_seconds.max(1)));
    });
}

pub fn start_reconcile(tx: Sender<ModuleUpdate>, reconcile_seconds: u64) {
    thread::spawn(move || loop {
        let (percent, status) = telemetry::battery();
        let _ = tx.send(ModuleUpdate::Battery { percent, status });
        send_audio(&tx);
        send_microphone(&tx);
        let _ = tx.send(ModuleUpdate::Brightness(telemetry::brightness()));
        send_network(&tx);
        send_bluetooth(&tx);
        refresh_notifications(&tx);
        let _ = tx.send(ModuleUpdate::Idle(telemetry::idle_inhibited()));
        thread::sleep(Duration::from_secs(reconcile_seconds.max(10)));
    });
}

pub fn cycle_power_profile() {
    glib::MainContext::default().spawn_local(async move {
        let result: zbus::Result<()> = async {
            let connection = zbus::Connection::system().await?;
            let proxy = Proxy::new(
                &connection,
                "net.hadess.PowerProfiles",
                "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles",
            )
            .await?;
            let current: String = proxy.get_property("ActiveProfile").await?;
            let next = match current.as_str() {
                "power-saver" => "balanced",
                "balanced" => "performance",
                _ => "power-saver",
            };
            proxy.set_property("ActiveProfile", &next).await?;
            Ok(())
        }
        .await;
        if let Err(error) = result {
            log::warn!("cycle power profile: {error}");
        }
    });
}

pub fn start_dbus(tx: Sender<ModuleUpdate>, coalesce_ms: u64) {
    start_power(tx.clone());
    start_battery(tx.clone());
    start_signal_refresh(
        tx.clone(),
        coalesce_ms,
        "org.freedesktop.NetworkManager",
        true,
    );
    start_signal_refresh(tx, coalesce_ms, "org.bluez", false);
}

fn start_power(tx: Sender<ModuleUpdate>) {
    glib::MainContext::default().spawn_local(async move {
        loop {
            let result: zbus::Result<()> = async {
                let connection = zbus::Connection::system().await?;
                let proxy = Proxy::new(
                    &connection,
                    "net.hadess.PowerProfiles",
                    "/net/hadess/PowerProfiles",
                    "net.hadess.PowerProfiles",
                )
                .await?;
                let profile: String = proxy.get_property("ActiveProfile").await?;
                let _ = tx.send(ModuleUpdate::Profile(profile));
                let mut changes = proxy
                    .receive_property_changed::<String>("ActiveProfile")
                    .await;
                while let Some(change) = changes.next().await {
                    let _ = tx.send(ModuleUpdate::Profile(change.get().await?));
                }
                Ok(())
            }
            .await;
            if let Err(error) = result {
                log::warn!("power profile events: {error}");
            }
            glib::timeout_future(Duration::from_secs(1)).await;
        }
    });
}

fn start_battery(tx: Sender<ModuleUpdate>) {
    glib::MainContext::default().spawn_local(async move { loop {
        let result: zbus::Result<()> = async {
            let connection=zbus::Connection::system().await?;
            let proxy=Proxy::new(&connection,"org.freedesktop.UPower","/org/freedesktop/UPower/devices/battery_BAT0","org.freedesktop.UPower.Device").await?;
            let (percent,status)=telemetry::battery(); let _=tx.send(ModuleUpdate::Battery{percent,status});
            let percentages=proxy.receive_property_changed::<f64>("Percentage").await.fuse();
            let states=proxy.receive_property_changed::<u32>("State").await.fuse();
            futures::pin_mut!(percentages,states);
            loop { futures::select! {
                value=percentages.next()=>if value.is_some(){let(percent,status)=telemetry::battery();let _=tx.send(ModuleUpdate::Battery{percent,status});}else{break},
                value=states.next()=>if value.is_some(){let(percent,status)=telemetry::battery();let _=tx.send(ModuleUpdate::Battery{percent,status});}else{break},
            }}
            Ok(())
        }.await;
        if let Err(error)=result { log::warn!("battery events: {error}"); }
        glib::timeout_future(Duration::from_secs(1)).await;
    }});
}

fn start_signal_refresh(
    tx: Sender<ModuleUpdate>,
    coalesce_ms: u64,
    sender: &'static str,
    network: bool,
) {
    glib::MainContext::default().spawn_local(async move {
        loop {
            let result: zbus::Result<()> = async {
                let connection = zbus::Connection::system().await?;
                let rule = MatchRule::builder()
                    .msg_type(MessageType::Signal)
                    .sender(sender)?
                    .build();
                let mut stream = MessageStream::for_match_rule(rule, &connection, Some(64)).await?;
                let mut last = Instant::now() - Duration::from_secs(1);
                while stream.try_next().await?.is_some() {
                    let wait = Duration::from_millis(coalesce_ms).saturating_sub(last.elapsed());
                    if !wait.is_zero() {
                        glib::timeout_future(wait).await;
                    }
                    while let Some(Ok(Some(_))) = stream.try_next().now_or_never() {}
                    let refresh_tx = tx.clone();
                    thread::spawn(move || {
                        if network {
                            send_network(&refresh_tx);
                        } else {
                            send_bluetooth(&refresh_tx);
                        }
                    });
                    last = Instant::now();
                }
                Ok(())
            }
            .await;
            if let Err(error) = result {
                log::warn!("{sender} events: {error}");
            }
            glib::timeout_future(Duration::from_secs(1)).await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clearing_workspace_alerts_clears_persistent_and_pulse_state() {
        let mut state = Snapshot::default();
        ModuleUpdate::WorkspaceAlert {
            workspace: 4,
            active: true,
        }
        .apply(&mut state);
        ModuleUpdate::WorkspaceAlertPulse {
            workspace: 4,
            active: false,
        }
        .apply(&mut state);
        assert!(state.workspace_alerts[3]);
        assert!(!state.workspace_alert_pulses[3]);
        ModuleUpdate::ClearWorkspaceAlerts.apply(&mut state);
        assert!(state.workspace_alerts.iter().all(|alert| !alert));
        assert!(state.workspace_alert_pulses.iter().all(|pulse| !pulse));
    }
}
