mod divergence;
mod events;
mod telemetry;
mod tray;

use anyhow::{Context, Result};
use chrono::{Local, Timelike};
use events::ModuleUpdate;
use futures::TryStreamExt;
use gtk::gdk;
use gtk::prelude::*;
use gtk_layer_shell::{self as layer_shell, Edge, Layer};
use serde::Deserialize;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::collections::VecDeque;
use std::fs;
use std::os::unix::net::UnixDatagram;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::thread;
use std::time::Duration;
use telemetry::Snapshot;

#[derive(Clone, Deserialize)]
struct Commands {
    network: String,
    network_advanced: String,
    bluetooth: String,
    audio_mixer: String,
}

#[derive(Clone, Deserialize)]
struct TrayConfig {
    blacklist: Vec<String>,
    pinned_first: Vec<String>,
}

#[derive(Clone, Deserialize)]
struct RefreshConfig {
    metrics_seconds: u64,
    llm_seconds: u64,
    reconcile_seconds: u64,
    event_coalesce_ms: u64,
}

#[derive(Clone, Deserialize)]
#[serde(default)]
struct DivergenceConfig {
    enabled: bool,
    monitors: String,
    roll_fps: u32,
}

impl Default for DivergenceConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            monitors: "all".into(),
            roll_fps: 20,
        }
    }
}

#[derive(Clone, Deserialize)]
struct Config {
    monitor: i32,
    height: i32,
    commands: Commands,
    tray: TrayConfig,
    refresh: RefreshConfig,
    #[serde(default)]
    divergence: DivergenceConfig,
}

#[derive(Clone)]
struct NotificationMeta {
    app: String,
    summary: String,
    workspace: Option<i32>,
}

#[derive(Clone, Deserialize)]
struct CandidateItem {
    label: String,
    text: String,
}

#[derive(Clone, Deserialize)]
#[serde(tag = "type")]
enum FcitxMessage {
    #[serde(rename = "status")]
    Status {
        active: bool,
        name: String,
        label: String,
    },
    #[serde(rename = "candidates")]
    Candidates {
        visible: bool,
        #[serde(default)]
        expanded: bool,
        #[serde(default)]
        x: i32,
        #[serde(default)]
        y: i32,
        #[serde(default = "default_scale")]
        scale: f64,
        #[serde(default)]
        preedit: String,
        #[serde(default)]
        aux: String,
        #[serde(default = "no_cursor")]
        cursor: i32,
        #[serde(default = "default_page")]
        page: i32,
        #[serde(default)]
        has_prev: bool,
        #[serde(default)]
        has_next: bool,
        #[serde(default)]
        items: Vec<CandidateItem>,
    },
}

fn default_scale() -> f64 {
    1.0
}
fn no_cursor() -> i32 {
    -1
}

fn candidate_width(value: &str, minimum: i32, maximum: i32) -> i32 {
    value
        .chars()
        .map(|ch| if ch.is_ascii() { 1 } else { 2 })
        .sum::<i32>()
        .clamp(minimum, maximum)
}
fn default_page() -> i32 {
    1
}

const WORKSPACE_GLYPHS: [&str; 10] = ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ"];

fn application_icon(class: &str) -> &'static str {
    match class {
        value if value.contains("firefox") => "󰈹",
        value if value.contains("chrom") || value.contains("brave") => "",
        value
            if value.contains("kitty")
                || value.contains("foot")
                || value.contains("alacritty")
                || value.contains("wezterm") =>
        {
            ""
        }
        value if value.contains("code") || value.contains("codium") => "󰨞",
        value if value.contains("discord") || value.contains("vesktop") => "󰙯",
        value
            if value.contains("thunar")
                || value.contains("nautilus")
                || value.contains("dolphin") =>
        {
            "󰉋"
        }
        value if value.contains("spotify") => "",
        value if value.contains("steam") => "",
        value if value.contains("obsidian") => "󰠮",
        value if value.contains("zathura") => "󰈦",
        value if value.contains("telegram") => "",
        value if value.contains("signal") => "󰭹",
        _ => "󰣆",
    }
}

fn workspace_label(index: usize, apps: &[String]) -> String {
    let mut icons = Vec::new();
    for class in apps {
        let icon = application_icon(class);
        if !icons.contains(&icon) {
            icons.push(icon);
        }
    }
    if icons.is_empty() {
        WORKSPACE_GLYPHS[index].into()
    } else {
        format!("{} {}", WORKSPACE_GLYPHS[index], icons.join(" "))
    }
}

fn battery_is_charging(status: &str) -> bool {
    status.trim().eq_ignore_ascii_case("charging")
}

fn battery_is_discharging(status: &str) -> bool {
    status.trim().eq_ignore_ascii_case("discharging")
}

fn battery_icon(percent: u64, status: &str) -> &'static str {
    if battery_is_charging(status) {
        "󰂄"
    } else if percent >= 90 {
        "󰁹"
    } else if percent >= 70 {
        "󰂀"
    } else if percent >= 40 {
        "󰁾"
    } else if percent >= 20 {
        "󰁼"
    } else {
        "󰂎"
    }
}

#[derive(Clone)]
struct Ui {
    workspace_buttons: Vec<gtk::Button>,
    system: gtk::Button,
    microphone_privacy: gtk::Button,
    system_panel: SystemPanelUi,
    clock_time: gtk::Label,
    clock_date: gtk::Label,
    input: gtk::Button,
    network: gtk::Button,
    network_icon: gtk::Label,
    network_name: gtk::Label,
    llm: gtk::Button,
    llm_detail: gtk::Label,
    audio: gtk::Button,
    power: gtk::Button,
    idle: gtk::Button,
    bluetooth: gtk::Button,
    notifications: gtk::Button,
}

#[derive(Clone)]
struct SystemPanelUi {
    window: gtk::Window,
    cpu: gtk::Label,
    memory: gtk::Label,
    temperature: gtk::Label,
    storage: gtk::Label,
    uptime: gtk::Label,
    brightness: gtk::Scale,
    brightness_value: gtk::Label,
    microphone: gtk::Scale,
    microphone_value: gtk::Label,
    microphone_mute: gtk::Button,
    microphone_device: gtk::Label,
    microphone_apps: gtk::Label,
    syncing_brightness: Rc<Cell<bool>>,
    syncing_microphone: Rc<Cell<bool>>,
}

#[derive(Clone, Default)]
struct PopupManager {
    active: Rc<RefCell<Option<gtk::Window>>>,
}

impl PopupManager {
    fn hide_internal(&self) {
        if let Some(active) = self.active.borrow_mut().take() {
            active.hide();
        }
    }

    fn dismiss(&self) {
        self.hide_internal();
        telemetry::spawn("pkill", &["-x", "nm-menu"]);
    }

    fn toggle(&self, popup: &gtk::Window, anchor: &gtk::Button, bar: &gtk::Window, width: i32) {
        let was_visible = popup.is_visible();
        self.dismiss();
        if was_visible {
            return;
        }

        position_popup(popup, anchor, bar, width);
        popup.show_all();
        self.active.borrow_mut().replace(popup.clone());
    }

    fn toggle_right(&self, popup: &gtk::Window, bar: &gtk::Window) {
        let was_visible = popup.is_visible();
        self.dismiss();
        if was_visible {
            return;
        }

        set_popup_monitor(popup, bar);
        layer_shell::set_anchor(popup, Edge::Left, false);
        layer_shell::set_anchor(popup, Edge::Right, true);
        layer_shell::set_margin(popup, Edge::Right, 0);
        popup.show_all();
        self.active.borrow_mut().replace(popup.clone());
    }
}

fn shell_words(command: &str) -> (String, Vec<String>) {
    let mut parts = command.split_whitespace();
    (
        parts.next().unwrap_or_default().to_string(),
        parts.map(str::to_string).collect(),
    )
}

fn run_command(command: &str) {
    let (program, args) = shell_words(command);
    if program.is_empty() {
        return;
    }
    let _ = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

fn run_positioned_command(command: &str, left: i32) {
    let (program, args) = shell_words(command);
    if program.is_empty() {
        return;
    }
    let _ = Command::new(program)
        .args(args)
        .env("NIXIE_POPUP_LEFT", left.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

fn focus_workspace(workspace: i32) {
    let dispatcher = format!("hl.dsp.focus({{ workspace = \"{workspace}\" }})");
    telemetry::spawn("hyprctl", &["dispatch", &dispatcher]);
}

fn button(class: &str) -> gtk::Button {
    let value = gtk::Button::new();
    value.style_context().add_class("module");
    for item in class.split_whitespace() {
        value.style_context().add_class(item);
    }
    value
}

fn label(text: &str, class: &str) -> gtk::Label {
    let value = gtk::Label::new(Some(text));
    for item in class.split_whitespace() {
        value.style_context().add_class(item);
    }
    value
}

fn hbox(spacing: i32) -> gtk::Box {
    gtk::Box::new(gtk::Orientation::Horizontal, spacing)
}
fn vbox(spacing: i32) -> gtk::Box {
    gtk::Box::new(gtk::Orientation::Vertical, spacing)
}

fn enable_transparency(win: &gtk::Window) {
    if let Some(screen) = WidgetExt::screen(win) {
        if let Some(visual) = screen.rgba_visual() {
            win.set_visual(Some(&visual));
        }
    }
}

fn popup(name: &str, width: i32, height: i32) -> gtk::Window {
    let win = gtk::Window::new(gtk::WindowType::Toplevel);
    enable_transparency(&win);
    win.set_widget_name(name);
    win.style_context().add_class("nixie-popover");
    win.set_default_size(width, height);
    layer_shell::init_for_window(&win);
    layer_shell::set_namespace(&win, name);
    layer_shell::set_layer(&win, Layer::Overlay);
    layer_shell::set_anchor(&win, Edge::Top, true);
    layer_shell::set_anchor(&win, Edge::Left, true);
    layer_shell::set_margin(&win, Edge::Top, 4);
    layer_shell::set_margin(&win, Edge::Left, 8);
    layer_shell::set_keyboard_interactivity(&win, false);
    win.connect_delete_event(|w, _| {
        w.hide();
        gtk::Inhibit(true)
    });
    win
}

fn popup_left(anchor: &gtk::Button, bar: &gtk::Window, width: i32) -> i32 {
    let x = anchor
        .translate_coordinates(bar, 0, 0)
        .map(|(x, _)| x)
        .unwrap_or(8);
    let centered = x + anchor.allocated_width() / 2 - width / 2;
    centered.clamp(8, (bar.allocated_width() - width - 8).max(8))
}

fn set_popup_monitor(popup: &gtk::Window, bar: &gtk::Window) {
    if let (Some(display), Some(surface)) = (gdk::Display::default(), bar.window()) {
        if let Some(monitor) = display.monitor_at_window(&surface) {
            layer_shell::set_monitor(popup, &monitor);
        }
    }
}

fn position_popup(popup: &gtk::Window, anchor: &gtk::Button, bar: &gtk::Window, width: i32) {
    set_popup_monitor(popup, bar);
    layer_shell::set_margin(popup, Edge::Left, popup_left(anchor, bar, width));
}

fn create_calendar() -> gtk::Window {
    let win = popup("nixie-calendar", 330, 280);
    let root = vbox(10);
    root.style_context().add_class("panel");
    root.pack_start(&label("Calendar", "panel-title"), false, false, 0);
    root.pack_start(&gtk::Calendar::new(), true, true, 0);
    win.add(&root);
    win
}

fn create_candidate_window() -> (gtk::Window, gtk::Box) {
    let win = gtk::Window::new(gtk::WindowType::Toplevel);
    enable_transparency(&win);
    win.set_widget_name("nixie-candidates");
    win.style_context().add_class("nixie-candidates");
    layer_shell::init_for_window(&win);
    layer_shell::set_namespace(&win, "nixie-candidates");
    layer_shell::set_layer(&win, Layer::Overlay);
    layer_shell::set_anchor(&win, Edge::Top, true);
    layer_shell::set_anchor(&win, Edge::Left, true);
    layer_shell::set_keyboard_interactivity(&win, false);
    let root = vbox(6);
    root.style_context().add_class("candidate-root");
    win.add(&root);
    (win, root)
}

fn update_candidates(win: &gtk::Window, root: &gtk::Box, message: FcitxMessage) {
    let FcitxMessage::Candidates {
        visible,
        expanded,
        x,
        y,
        scale,
        preedit,
        aux,
        cursor,
        page,
        has_prev,
        has_next,
        items,
    } = message
    else {
        return;
    };
    if !visible {
        win.hide();
        return;
    }
    for child in root.children() {
        root.remove(&child);
    }
    let heading = [preedit, aux]
        .into_iter()
        .filter(|v| !v.is_empty())
        .collect::<Vec<_>>()
        .join("  ");
    if !heading.is_empty() {
        let value = label(&heading, "candidate-preedit");
        value.set_xalign(0.0);
        root.pack_start(&value, false, false, 0);
    }
    if expanded {
        let grid = gtk::Grid::new();
        grid.set_column_spacing(5);
        grid.set_row_spacing(5);
        let cell_width = items
            .iter()
            .take(25)
            .map(|item| candidate_width(&format!("{} {}", item.label, item.text), 6, 28))
            .max()
            .unwrap_or(6);
        for (index, item) in items.iter().take(25).enumerate() {
            let value = label(&format!("{} {}", item.label, item.text), "candidate-item");
            value.set_xalign(0.0);
            value.set_hexpand(true);
            value.set_width_chars(cell_width);
            value.set_max_width_chars(cell_width);
            value.set_ellipsize(gtk::pango::EllipsizeMode::End);
            if index as i32 == cursor {
                value.style_context().add_class("selected");
            }
            grid.attach(&value, (index % 5) as i32, (index / 5) as i32, 1, 1);
        }
        root.pack_start(&grid, false, false, 0);
        let mut page_parts = Vec::new();
        if has_prev {
            page_parts.push("↑ previous");
        }
        page_parts.push("Ctrl+Enter 原樣輸出");
        page_parts.push(if has_next { "↓ more" } else { "end" });
        let footer = label(
            &format!("page {}  ·  {}", page.max(1), page_parts.join("  ·  ")),
            "candidate-page",
        );
        footer.set_xalign(0.0);
        root.pack_start(&footer, false, false, 0);
    } else {
        let row = hbox(4);
        for (index, item) in items.iter().take(7).enumerate() {
            let content = format!("{} {}", item.label, item.text);
            let width = candidate_width(&content, 4, 20);
            let value = label(&content, "candidate-item");
            value.set_width_chars(width);
            value.set_max_width_chars(width);
            value.set_ellipsize(gtk::pango::EllipsizeMode::End);
            if index as i32 == cursor {
                value.style_context().add_class("selected");
            }
            row.pack_start(&value, false, false, 0);
        }
        root.pack_start(&row, false, false, 0);
        let hint = label("Ctrl+Enter  注音原樣輸出", "candidate-page");
        hint.set_xalign(0.0);
        root.pack_start(&hint, false, false, 0);
    }
    win.show_all();
    let divisor = scale.max(1.0);
    let cursor_x = (x as f64 / divisor).round() as i32;
    let cursor_y = (y as f64 / divisor).round() as i32;
    let missing_cursor = cursor_x <= 1 && cursor_y <= 1;
    let (_, natural_width) = root.preferred_width();
    let (_, natural_height) = root.preferred_height();
    if let Some(display) = gdk::Display::default() {
        if let Some(monitor) = display.monitor_at_point(cursor_x, cursor_y) {
            let geometry = monitor.geometry();
            layer_shell::set_monitor(win, &monitor);
            if missing_cursor {
                layer_shell::set_margin(win, Edge::Left, 24);
                layer_shell::set_margin(
                    win,
                    Edge::Top,
                    (geometry.height() - natural_height - 72).max(50),
                );
                return;
            }
            let relative_x = cursor_x - geometry.x();
            let relative_y = cursor_y - geometry.y();
            let left = relative_x.clamp(8, (geometry.width() - natural_width - 8).max(8));
            let below = relative_y + 7;
            let top = if below + natural_height <= geometry.height() - 8 {
                below
            } else {
                (relative_y - natural_height - 7).max(8)
            };
            layer_shell::set_margin(win, Edge::Left, left);
            layer_shell::set_margin(win, Edge::Top, top);
            return;
        }
    }
    layer_shell::set_margin(win, Edge::Left, cursor_x.max(8));
    layer_shell::set_margin(win, Edge::Top, (cursor_y + 7).max(50));
}

fn create_llm_panel() -> (gtk::Window, gtk::Label) {
    let win = popup("nixie-llm", 370, 250);
    let root = vbox(12);
    root.style_context().add_class("panel");
    root.pack_start(&label("Local AI usage", "panel-title"), false, false, 0);
    let detail = label("Collecting usage…", "");
    detail.set_xalign(0.0);
    detail.set_line_wrap(true);
    root.pack_start(&detail, true, true, 0);
    let open = button("panel-action");
    open.set_label("Open Codex directory");
    open.connect_clicked(|_| telemetry::spawn("xdg-open", &["/home/brine/.codex"]));
    root.pack_end(&open, false, false, 0);
    win.add(&root);
    (win, detail)
}

fn metric_row(icon: &str, title: &str, value: &gtk::Label) -> gtk::Box {
    let row = hbox(10);
    let icon = label(icon, "system-icon");
    let title = label(title, "");
    title.set_xalign(0.0);
    title.set_hexpand(true);
    value.set_xalign(1.0);
    row.pack_start(&icon, false, false, 0);
    row.pack_start(&title, true, true, 0);
    row.pack_end(value, false, false, 0);
    row
}

fn confirmed_action(
    label_text: &'static str,
    program: &'static str,
    args: &'static [&'static str],
) -> gtk::Button {
    let action = button("session-action");
    action.set_label(label_text);
    let armed = Rc::new(Cell::new(false));
    let generation = Rc::new(Cell::new(0u64));
    let armed_ref = armed.clone();
    let generation_ref = generation.clone();
    action.connect_clicked(move |button| {
        if armed_ref.replace(false) {
            generation_ref.set(generation_ref.get().wrapping_add(1));
            telemetry::spawn(program, args);
            button.set_label(label_text);
            return;
        }
        armed_ref.set(true);
        button.set_label(&format!("Confirm {label_text}"));
        let token = generation_ref.get().wrapping_add(1);
        generation_ref.set(token);
        let reset_button = button.clone();
        let reset_armed = armed_ref.clone();
        let reset_generation = generation_ref.clone();
        glib::timeout_add_local_once(Duration::from_secs(5), move || {
            if reset_generation.get() == token {
                reset_armed.set(false);
                reset_button.set_label(label_text);
            }
        });
    });
    action
}

fn create_system_panel(updates: glib::Sender<ModuleUpdate>) -> SystemPanelUi {
    let win = popup("nixie-system", 430, 600);
    let root = vbox(12);
    root.style_context().add_class("panel");
    root.pack_start(&label("System", "panel-title"), false, false, 0);

    let metrics = vbox(8);
    metrics.style_context().add_class("system-section");
    let cpu = label("--%", "metric-value");
    let memory = label("--%", "metric-value");
    let temperature = label("--°", "metric-value");
    let storage = label("--%", "metric-value");
    let uptime = label("--", "metric-value");
    metrics.pack_start(&metric_row("󰘚", "CPU usage", &cpu), false, false, 0);
    metrics.pack_start(&metric_row("󰍛", "Memory usage", &memory), false, false, 0);
    metrics.pack_start(
        &metric_row("󰔏", "Temperature", &temperature),
        false,
        false,
        0,
    );
    metrics.pack_start(&metric_row("󰋊", "Root storage", &storage), false, false, 0);
    metrics.pack_start(&metric_row("󰥔", "Uptime", &uptime), false, false, 0);
    root.pack_start(&metrics, false, false, 0);

    let controls = vbox(8);
    controls.style_context().add_class("system-section");
    let brightness_title = hbox(8);
    brightness_title.pack_start(&label("󰃠", "system-icon"), false, false, 0);
    let brightness_name = label("Brightness", "");
    brightness_name.set_hexpand(true);
    brightness_name.set_xalign(0.0);
    brightness_title.pack_start(&brightness_name, true, true, 0);
    let brightness_value = label("--%", "metric-value");
    brightness_title.pack_end(&brightness_value, false, false, 0);
    controls.pack_start(&brightness_title, false, false, 0);
    let brightness = gtk::Scale::with_range(gtk::Orientation::Horizontal, 1.0, 100.0, 1.0);
    brightness.set_draw_value(false);
    let syncing_brightness = Rc::new(Cell::new(false));
    let brightness_generation = Rc::new(Cell::new(0u64));
    let syncing_ref = syncing_brightness.clone();
    let generation_ref = brightness_generation.clone();
    brightness.connect_value_changed(move |scale| {
        if syncing_ref.get() {
            return;
        }
        let value = scale.value().round() as u64;
        let token = generation_ref.get().wrapping_add(1);
        generation_ref.set(token);
        let generation = generation_ref.clone();
        glib::timeout_add_local_once(Duration::from_millis(90), move || {
            if generation.get() == token {
                telemetry::spawn("brightnessctl", &["set", &format!("{value}%")]);
            }
        });
    });
    controls.pack_start(&brightness, false, false, 0);

    let microphone_title = hbox(8);
    microphone_title
        .style_context()
        .add_class("microphone-controls");
    let microphone_mute = button("panel-action microphone-mute");
    microphone_mute.set_label("󰍬");
    microphone_mute.set_tooltip_text(Some("Mute microphone"));
    microphone_mute.connect_clicked(|_| {
        telemetry::spawn("wpctl", &["set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
    });
    microphone_title.pack_start(&microphone_mute, false, false, 0);
    let microphone_name = label("Microphone", "");
    microphone_name.set_hexpand(true);
    microphone_name.set_xalign(0.0);
    microphone_title.pack_start(&microphone_name, true, true, 0);
    let microphone_value = label("--%", "metric-value");
    microphone_title.pack_end(&microphone_value, false, false, 0);
    controls.pack_start(&microphone_title, false, false, 0);
    let microphone = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 100.0, 1.0);
    microphone.set_draw_value(false);
    let syncing_microphone = Rc::new(Cell::new(false));
    let microphone_generation = Rc::new(Cell::new(0u64));
    let syncing_ref = syncing_microphone.clone();
    let generation_ref = microphone_generation.clone();
    microphone.connect_value_changed(move |scale| {
        if syncing_ref.get() {
            return;
        }
        let value = scale.value().round() as u64;
        let token = generation_ref.get().wrapping_add(1);
        generation_ref.set(token);
        let generation = generation_ref.clone();
        glib::timeout_add_local_once(Duration::from_millis(90), move || {
            if generation.get() == token {
                telemetry::spawn(
                    "wpctl",
                    &["set-volume", "@DEFAULT_AUDIO_SOURCE@", &format!("{value}%")],
                );
            }
        });
    });
    controls.pack_start(&microphone, false, false, 0);
    let microphone_device = label("No input device", "muted device-name");
    microphone_device.set_xalign(0.0);
    microphone_device.set_ellipsize(gtk::pango::EllipsizeMode::Middle);
    controls.pack_start(&microphone_device, false, false, 0);
    let microphone_apps = label(
        "No applications are using the microphone",
        "muted capture-apps",
    );
    microphone_apps.set_xalign(0.0);
    microphone_apps.set_line_wrap(true);
    controls.pack_start(&microphone_apps, false, false, 0);
    root.pack_start(&controls, false, false, 0);

    let footer = gtk::Grid::new();
    footer.set_column_spacing(5);
    footer.set_row_spacing(5);
    footer.style_context().add_class("session-footer");
    let lock = button("session-action");
    lock.set_label("Lock");
    lock.connect_clicked(|_| telemetry::spawn("hyprlock", &[]));
    let suspend = button("session-action");
    suspend.set_label("Suspend");
    suspend.connect_clicked(|_| {
        thread::spawn(|| {
            telemetry::spawn("hyprlock", &[]);
            thread::sleep(Duration::from_millis(500));
            telemetry::spawn("systemctl", &["suspend"]);
        });
    });
    let hibernate = button("session-action disabled");
    hibernate.set_label("Hibernate");
    hibernate.set_sensitive(false);
    hibernate.set_tooltip_text(Some(
        "Disabled: persistent swap and resume support are not configured",
    ));
    let logout = confirmed_action("Log out", "hyprctl", &["dispatch", "hl.dsp.exit()"]);
    let reboot = confirmed_action("Reboot", "systemctl", &["reboot"]);
    let poweroff = confirmed_action("Power off", "systemctl", &["poweroff"]);
    for (index, action) in [&lock, &suspend, &hibernate, &logout, &reboot, &poweroff]
        .into_iter()
        .enumerate()
    {
        action.set_hexpand(true);
        footer.attach(action, (index % 3) as i32, (index / 3) as i32, 1, 1);
    }
    root.pack_end(&footer, false, false, 0);
    win.add(&root);

    let refresh_win = win.clone();
    glib::timeout_add_local(Duration::from_secs(3), move || {
        if refresh_win.is_visible() {
            events::refresh_extended_system(&updates);
        }
        glib::Continue(true)
    });
    SystemPanelUi {
        window: win,
        cpu,
        memory,
        temperature,
        storage,
        uptime,
        brightness,
        brightness_value,
        microphone,
        microphone_value,
        microphone_mute,
        microphone_device,
        microphone_apps,
        syncing_brightness,
        syncing_microphone,
    }
}

fn format_uptime(seconds: u64) -> String {
    let days = seconds / 86_400;
    let hours = (seconds % 86_400) / 3_600;
    let minutes = (seconds % 3_600) / 60;
    if days > 0 {
        format!("{days}d {hours}h")
    } else {
        format!("{hours}h {minutes}m")
    }
}

fn refresh_notification_rows(list: &gtk::Box, metadata: &Rc<RefCell<VecDeque<NotificationMeta>>>) {
    for child in list.children() {
        list.remove(&child);
    }
    let history = telemetry::history();
    if history.is_empty() {
        let empty = label("No notifications", "muted");
        empty.set_margin_top(24);
        list.pack_start(&empty, false, false, 0);
    }
    for item in history.into_iter().take(30) {
        let row = button("panel-row");
        let content = vbox(3);
        let top = hbox(8);
        let summary = label(&item.summary, "");
        summary.set_xalign(0.0);
        summary.set_hexpand(true);
        summary.set_single_line_mode(true);
        summary.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let app = label(&item.app, "muted");
        top.pack_start(&summary, true, true, 0);
        top.pack_end(&app, false, false, 0);
        content.pack_start(&top, false, false, 0);
        if !item.body.is_empty() {
            let body = label(&item.body, "muted");
            body.set_xalign(0.0);
            body.set_line_wrap(true);
            body.set_lines(4);
            body.set_ellipsize(gtk::pango::EllipsizeMode::End);
            body.set_max_width_chars(72);
            content.pack_start(&body, false, false, 0);
        }
        row.add(&content);
        let target = metadata
            .borrow()
            .iter()
            .rev()
            .find(|m| {
                (m.app.is_empty() || item.app.contains(&m.app) || m.app.contains(&item.app))
                    && (m.summary.is_empty() || m.summary == item.summary)
            })
            .and_then(|m| m.workspace);
        let id = item.id;
        let tip = target
            .map(|w| format!("Open from workspace {w}"))
            .unwrap_or_else(|| "Restore notification".into());
        row.set_tooltip_text(Some(&tip));
        row.connect_clicked(move |_| {
            if let Some(workspace) = target {
                focus_workspace(workspace);
            }
            telemetry::spawn("dunstctl", &["history-pop", &id.to_string()]);
        });
        list.pack_start(&row, false, false, 0);
    }
    list.show_all();
}

fn refresh_notifications_after(tx: glib::Sender<ModuleUpdate>, delay_ms: u64) {
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(delay_ms));
        events::refresh_notifications(&tx);
    });
}

fn create_notification_panel(
    metadata: Rc<RefCell<VecDeque<NotificationMeta>>>,
    indicator: gtk::Button,
    updates: glib::Sender<ModuleUpdate>,
) -> (gtk::Window, gtk::Box) {
    let win = popup("nixie-notifications", 560, 820);
    win.set_resizable(false);
    win.set_size_request(560, 820);
    let root = vbox(10);
    root.set_size_request(528, 788);
    root.style_context().add_class("panel");
    let title = hbox(8);
    let heading = label("Notifications", "panel-title");
    heading.set_hexpand(true);
    heading.set_xalign(0.0);
    let dnd = button("panel-action");
    dnd.set_label("󰂛");
    dnd.set_tooltip_text(Some("Toggle do not disturb"));
    let dnd_updates = updates.clone();
    dnd.connect_clicked(move |_| {
        telemetry::spawn("dunstctl", &["set-paused", "toggle"]);
        refresh_notifications_after(dnd_updates.clone(), 75);
    });
    let clear = button("panel-action");
    clear.set_label("󰆴");
    clear.set_tooltip_text(Some("Clear notification history"));
    let clear_updates = updates.clone();
    clear.connect_clicked(move |_| {
        telemetry::spawn("dunstctl", &["history-clear"]);
        indicator.set_label("󰂚");
        indicator.style_context().remove_class("unread");
        let _ = clear_updates.send(ModuleUpdate::ClearWorkspaceAlerts);
        refresh_notifications_after(clear_updates.clone(), 75);
    });
    title.pack_start(&heading, true, true, 0);
    title.pack_end(&clear, false, false, 0);
    title.pack_end(&dnd, false, false, 0);
    root.pack_start(&title, false, false, 0);
    let scroll = gtk::ScrolledWindow::new(None::<&gtk::Adjustment>, None::<&gtk::Adjustment>);
    scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scroll.set_min_content_height(730);
    let list = vbox(8);
    scroll.add(&list);
    root.pack_start(&scroll, true, true, 0);
    win.add(&root);
    let list_ref = list.clone();
    let meta_ref = metadata.clone();
    win.connect_show(move |_| refresh_notification_rows(&list_ref, &meta_ref));
    (win, list)
}

fn monitor_notifications(tx: glib::Sender<NotificationMeta>, updates: glib::Sender<ModuleUpdate>) {
    glib::MainContext::default().spawn_local(async move { loop {
        let result: zbus::Result<()> = async {
            let connection = zbus::Connection::session().await?;
            let rules = [
                "type='method_call',interface='org.freedesktop.Notifications',member='Notify'",
                "type='signal',interface='org.freedesktop.Notifications',member='NotificationClosed'",
            ];
            connection.call_method(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", Some("org.freedesktop.DBus.Monitoring"), "BecomeMonitor", &(&rules[..], 0u32)).await?;
            let mut stream = zbus::MessageStream::from(connection.clone());
            while let Some(message) = stream.try_next().await? {
                if message.interface().as_ref().map(|v| v.as_str()) != Some("org.freedesktop.Notifications") { continue; }
                if message.member().as_ref().map(|v| v.as_str()) == Some("Notify") {
                    type NotifyBody = (String, u32, String, String, String, Vec<String>, HashMap<String, zbus::zvariant::OwnedValue>, i32);
                    if let Ok((app, _, _, summary, _, _, hints, _)) = message.body::<NotifyBody>() {
                        let desktop_entry = hints.get("desktop-entry")
                            .and_then(|value| <&str>::try_from(value).ok())
                            .map(str::to_string);
                        let hinted_pid = hints.get("sender-pid")
                            .or_else(|| hints.get("pid"))
                            .and_then(|value| u32::try_from(value).ok());
                        let sender = message.header().ok()
                            .and_then(|header| header.sender().ok().flatten().map(ToString::to_string));
                        let pid = if hinted_pid.is_some() { hinted_pid } else if let Some(sender) = sender {
                            connection.call_method(
                                Some("org.freedesktop.DBus"),
                                "/org/freedesktop/DBus",
                                Some("org.freedesktop.DBus"),
                                "GetConnectionUnixProcessID",
                                &(sender,),
                            ).await.ok().and_then(|reply| reply.body::<u32>().ok())
                        } else { None };
                        let workspace = telemetry::notification_workspace(
                            &telemetry::NotificationIdentifiers { pid, desktop_entry, app: app.clone() },
                            &telemetry::hypr_clients(),
                        );
                        let _ = tx.send(NotificationMeta { app, summary, workspace });
                    }
                }
                refresh_notifications_after(updates.clone(), 75);
            }
            Ok(())
        }.await;
        if let Err(error) = result { log::warn!("notification monitor stopped: {error}"); }
        glib::timeout_future_seconds(2).await;
    }});
}

fn monitor_input(tx: glib::Sender<FcitxMessage>) {
    thread::spawn(move || {
        let running = !telemetry::output("pgrep", &["-x", "fcitx5"])
            .trim()
            .is_empty();
        let state = if running {
            telemetry::output("fcitx5-remote", &[])
                .trim()
                .parse::<i32>()
                .unwrap_or(1)
        } else {
            1
        };
        let name = if running {
            telemetry::output("fcitx5-remote", &["-n"])
                .trim()
                .to_string()
        } else {
            "keyboard-us".into()
        };
        let label = if state != 2 {
            "EN"
        } else if name.contains("keyboard-de") {
            "DE"
        } else if name.contains("rime") || name.contains("chewing") {
            "中"
        } else if name.contains("mozc") {
            "日"
        } else {
            "EN"
        };
        let _ = tx.send(FcitxMessage::Status {
            active: state == 2,
            name,
            label: label.into(),
        });
        let runtime = std::env::var("XDG_RUNTIME_DIR")
            .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::geteuid() }));
        let socket_path = PathBuf::from(runtime).join("nixie-fcitx.sock");
        let _ = fs::remove_file(&socket_path);
        let Ok(socket) = UnixDatagram::bind(&socket_path) else {
            log::warn!("cannot bind input-method event socket");
            return;
        };
        loop {
            let mut data = [0u8; 65535];
            match socket.recv(&mut data) {
                Ok(size) => {
                    if let Ok(value) = serde_json::from_slice::<FcitxMessage>(&data[..size]) {
                        if tx.send(value).is_err() {
                            break;
                        }
                    }
                }
                Err(error) => {
                    log::warn!("input-method event socket: {error}");
                    break;
                }
            }
        }
        let _ = fs::remove_file(socket_path);
    });
}

fn build_bar(
    config: &Config,
    metadata: Rc<RefCell<VecDeque<NotificationMeta>>>,
    updates: glib::Sender<ModuleUpdate>,
) -> (gtk::Window, Ui) {
    let win = gtk::Window::new(gtk::WindowType::Toplevel);
    win.style_context().add_class("nixie-bar");
    layer_shell::init_for_window(&win);
    layer_shell::set_namespace(&win, "nixie-shell");
    layer_shell::set_layer(&win, Layer::Top);
    layer_shell::set_anchor(&win, Edge::Top, true);
    layer_shell::set_anchor(&win, Edge::Left, true);
    layer_shell::set_anchor(&win, Edge::Right, true);
    layer_shell::auto_exclusive_zone_enable(&win);
    win.set_default_size(1, config.height);
    layer_shell::set_keyboard_interactivity(&win, false);
    if let Some(display) = gdk::Display::default() {
        if let Some(monitor) = display.monitor(config.monitor) {
            layer_shell::set_monitor(&win, &monitor);
        }
    }
    let center = gtk::Overlay::new();
    center.style_context().add_class("bar-root");
    let left = hbox(7);
    left.style_context().add_class("bar-left");
    let right = hbox(7);
    right.style_context().add_class("bar-right");
    let popups = PopupManager::default();

    let workspaces = hbox(3);
    let mut workspace_buttons = Vec::new();
    for (id, glyph) in WORKSPACE_GLYPHS.iter().enumerate() {
        let id = id as i32 + 1;
        let b = button("workspace");
        b.set_label(glyph);
        if id > 3 {
            b.set_no_show_all(true);
            b.hide();
        }
        b.set_tooltip_text(Some(&format!("Workspace {id}")));
        let workspace_popups = popups.clone();
        b.connect_clicked(move |_| {
            workspace_popups.dismiss();
            focus_workspace(id);
        });
        workspaces.pack_start(&b, false, false, 0);
        workspace_buttons.push(b);
    }
    let system = button("system");
    system.set_label("󰒋");
    system.set_tooltip_text(Some("CPU --% · Memory --% · Temperature --°"));
    let system_panel = create_system_panel(updates.clone());
    let system_ref = system_panel.window.clone();
    let system_bar = win.clone();
    let system_popups = popups.clone();
    let system_updates = updates.clone();
    system.connect_clicked(move |button| {
        events::refresh_extended_system(&system_updates);
        system_popups.toggle(&system_ref, button, &system_bar, 430);
    });
    left.pack_start(&system, false, false, 0);
    let microphone_privacy = button("microphone-privacy");
    microphone_privacy.set_label("󰍬");
    microphone_privacy.set_no_show_all(true);
    microphone_privacy.hide();
    let mic_ref = system_panel.window.clone();
    let mic_bar = win.clone();
    let mic_popups = popups.clone();
    let mic_scale = system_panel.microphone.clone();
    let mic_updates = updates.clone();
    microphone_privacy.connect_clicked(move |button| {
        events::refresh_extended_system(&mic_updates);
        mic_popups.toggle(&mic_ref, button, &mic_bar, 430);
        mic_scale.grab_focus();
    });
    left.pack_start(&microphone_privacy, false, false, 0);
    let idle = button("idle");
    idle.set_label("󰌽");
    idle.set_tooltip_text(Some("Idle inhibitor · click to toggle"));
    let idle_updates = updates.clone();
    let idle_popups = popups.clone();
    idle.connect_clicked(move |_| {
        idle_popups.dismiss();
        run_command("/home/brine/.config/nixie-shell/bin/toggle-idle");
        let tx = idle_updates.clone();
        thread::spawn(move || {
            thread::sleep(Duration::from_millis(75));
            let _ = tx.send(ModuleUpdate::Idle(telemetry::idle_inhibited()));
        });
    });
    left.pack_start(&idle, false, false, 0);
    left.pack_start(&workspaces, false, false, 0);

    let clock = button("clock");
    clock.set_height_request(config.height);
    let clock_box = hbox(7);
    let clock_time = label("--:--", "clock-time");
    let clock_date = label("--.--", "clock-date");
    clock_box.pack_start(&clock_time, false, false, 0);
    clock_box.pack_start(&clock_date, false, false, 0);
    clock.add(&clock_box);
    let calendar = create_calendar();
    let cal_ref = calendar.clone();
    let cal_bar = win.clone();
    let cal_popups = popups.clone();
    clock.connect_clicked(move |button| cal_popups.toggle(&cal_ref, button, &cal_bar, 330));

    let input = button("input");
    input.set_label("EN");
    input.set_tooltip_text(Some("Input method"));
    let input_popups = popups.clone();
    input.connect_clicked(move |_| {
        input_popups.dismiss();
        telemetry::spawn("fcitx5-remote", &["-t"]);
    });
    right.pack_start(&input, false, false, 0);
    let network = button("network");
    let network_box = hbox(7);
    let network_icon = label("󰖪", "network-icon");
    let network_name = label("Network", "");
    network_box.pack_start(&network_icon, false, false, 0);
    network_box.pack_start(&network_name, false, false, 0);
    network.add(&network_box);
    let net_cmd = config.commands.network.clone();
    let net_bar = win.clone();
    let net_popups = popups.clone();
    network.connect_clicked(move |button| {
        net_popups.hide_internal();
        run_positioned_command(&net_cmd, popup_left(button, &net_bar, 360));
    });
    let advanced = config.commands.network_advanced.clone();
    let advanced_popups = popups.clone();
    network.connect_button_press_event(move |_, e| {
        if e.button() == 3 {
            advanced_popups.dismiss();
            run_command(&advanced);
            gtk::Inhibit(true)
        } else {
            gtk::Inhibit(false)
        }
    });
    right.pack_start(&network, false, false, 0);
    let tray_box = hbox(2);
    tray_box.style_context().add_class("tray");
    right.pack_start(&tray_box, false, false, 0);
    tray::start(
        &tray_box,
        config.tray.blacklist.clone(),
        config.tray.pinned_first.clone(),
    );
    let llm = button("llm");
    llm.set_label("AI --");
    let (llm_panel, llm_detail) = create_llm_panel();
    let llm_ref = llm_panel.clone();
    let llm_bar = win.clone();
    let llm_popups = popups.clone();
    llm.connect_clicked(move |button| llm_popups.toggle(&llm_ref, button, &llm_bar, 370));
    right.pack_start(&llm, false, false, 0);
    let audio = button("audio");
    audio.set_label("󰕾 --");
    let audio_popups = popups.clone();
    audio.connect_clicked(move |_| {
        audio_popups.dismiss();
        telemetry::spawn("wpctl", &["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
    });
    let mixer = config.commands.audio_mixer.clone();
    let mixer_popups = popups.clone();
    audio.connect_button_press_event(move |_, e| {
        if e.button() == 3 {
            mixer_popups.dismiss();
            run_command(&mixer);
            gtk::Inhibit(true)
        } else {
            gtk::Inhibit(false)
        }
    });
    audio.add_events(gdk::EventMask::SCROLL_MASK | gdk::EventMask::SMOOTH_SCROLL_MASK);
    let smooth_volume_scroll = Rc::new(RefCell::new(0.0));
    audio.connect_scroll_event(move |_, event| {
        let (change, handled) = match event.direction() {
            gdk::ScrollDirection::Up => (Some("5%+"), true),
            gdk::ScrollDirection::Down => (Some("5%-"), true),
            gdk::ScrollDirection::Smooth => {
                let (_, delta_y) = event.delta();
                let mut accumulated = smooth_volume_scroll.borrow_mut();
                *accumulated += delta_y;
                if *accumulated <= -1.0 {
                    *accumulated += 1.0;
                    (Some("5%+"), true)
                } else if *accumulated >= 1.0 {
                    *accumulated -= 1.0;
                    (Some("5%-"), true)
                } else {
                    (None, true)
                }
            }
            _ => (None, false),
        };
        if let Some(change) = change {
            telemetry::spawn(
                "wpctl",
                &[
                    "set-volume",
                    "--limit",
                    "1.0",
                    "@DEFAULT_AUDIO_SINK@",
                    change,
                ],
            );
        }
        gtk::Inhibit(handled)
    });
    right.pack_start(&audio, false, false, 0);
    let power = button("power");
    power.set_label("󰾅 󰁹 --");
    let power_popups = popups.clone();
    power.connect_clicked(move |_| {
        power_popups.dismiss();
        events::cycle_power_profile();
    });
    right.pack_start(&power, false, false, 0);
    let bluetooth = button("bluetooth");
    bluetooth.set_label("󰂯");
    let bt_cmd = config.commands.bluetooth.clone();
    let bluetooth_popups = popups.clone();
    bluetooth.connect_clicked(move |_| {
        bluetooth_popups.dismiss();
        run_command(&bt_cmd);
    });
    right.pack_start(&bluetooth, false, false, 0);
    let notifications = button("notifications");
    notifications.set_label("󰂚");
    let (notification_panel, _) =
        create_notification_panel(metadata, notifications.clone(), updates.clone());
    let nref = notification_panel.clone();
    let notification_bar = win.clone();
    let notification_popups = popups.clone();
    notifications
        .connect_clicked(move |_| notification_popups.toggle_right(&nref, &notification_bar));
    let notification_updates = updates.clone();
    notifications.connect_button_press_event(move |_, e| {
        if e.button() == 3 {
            telemetry::spawn("dunstctl", &["set-paused", "toggle"]);
            refresh_notifications_after(notification_updates.clone(), 75);
            gtk::Inhibit(true)
        } else {
            gtk::Inhibit(false)
        }
    });
    right.pack_start(&notifications, false, false, 0);

    left.set_hexpand(true);
    right.set_hexpand(false);
    right.set_halign(gtk::Align::End);
    let base = hbox(0);
    base.pack_start(&left, true, true, 0);
    base.pack_end(&right, false, false, 0);
    center.add(&base);
    clock.set_halign(gtk::Align::Center);
    clock.set_valign(gtk::Align::Fill);
    center.add_overlay(&clock);
    win.add(&center);
    (
        win,
        Ui {
            workspace_buttons,
            system,
            microphone_privacy,
            system_panel,
            clock_time,
            clock_date,
            input,
            network,
            network_icon,
            network_name,
            llm,
            llm_detail,
            audio,
            power,
            idle,
            bluetooth,
            notifications,
        },
    )
}

fn update_ui(ui: &Ui, s: &Snapshot, update: &ModuleUpdate) {
    if matches!(
        update,
        ModuleUpdate::Workspace(_)
            | ModuleUpdate::WorkspaceApps(_)
            | ModuleUpdate::WorkspaceAlert { .. }
            | ModuleUpdate::WorkspaceAlertPulse { .. }
            | ModuleUpdate::ClearWorkspaceAlerts
    ) {
        for (idx, b) in ui.workspace_buttons.iter().enumerate() {
            let apps = s.workspace_apps.get(idx).map(Vec::as_slice).unwrap_or(&[]);
            let alerted = s.workspace_alerts.get(idx).copied().unwrap_or(false);
            let pulse = s.workspace_alert_pulses.get(idx).copied().unwrap_or(false);
            b.set_visible(
                idx < 3 || !apps.is_empty() || alerted || s.workspace == (idx + 1) as i32,
            );
            b.set_label(&workspace_label(idx, apps));
            b.set_tooltip_text(Some(&if apps.is_empty() {
                format!("Workspace {}", idx + 1)
            } else {
                format!("Workspace {} · {}", idx + 1, apps.join(", "))
            }));
            if s.workspace == (idx + 1) as i32 {
                b.style_context().add_class("active");
            } else {
                b.style_context().remove_class("active");
            }
            if alerted && pulse && s.workspace != (idx + 1) as i32 {
                b.style_context().add_class("notification-alert");
            } else {
                b.style_context().remove_class("notification-alert");
            }
        }
    }
    if matches!(update, ModuleUpdate::Metrics { .. }) {
        ui.system.set_tooltip_text(Some(&format!(
            "CPU {}% · Memory {}% · Temperature {}°C",
            s.cpu, s.mem, s.temp
        )));
        ui.system_panel.cpu.set_text(&format!("{}%", s.cpu));
        ui.system_panel.memory.set_text(&format!("{}%", s.mem));
        ui.system_panel
            .temperature
            .set_text(&format!("{}°C", s.temp));
    }
    if matches!(update, ModuleUpdate::ExtendedSystem { .. }) {
        ui.system_panel.storage.set_text(&format!("{}%", s.storage));
        ui.system_panel.uptime.set_text(&format_uptime(s.uptime));
    }
    if matches!(update, ModuleUpdate::Brightness(_)) {
        ui.system_panel.syncing_brightness.set(true);
        ui.system_panel.brightness.set_value(s.brightness as f64);
        ui.system_panel.syncing_brightness.set(false);
        ui.system_panel
            .brightness_value
            .set_text(&format!("{}%", s.brightness));
    }
    if matches!(update, ModuleUpdate::Microphone { .. }) {
        ui.system_panel.syncing_microphone.set(true);
        ui.system_panel
            .microphone
            .set_value(s.microphone_volume as f64);
        ui.system_panel.syncing_microphone.set(false);
        ui.system_panel
            .microphone_value
            .set_text(&format!("{}%", s.microphone_volume));
        ui.system_panel
            .microphone_mute
            .set_label(if s.microphone_muted { "󰍭" } else { "󰍬" });
        ui.system_panel
            .microphone_mute
            .set_tooltip_text(Some(if s.microphone_muted {
                "Unmute microphone"
            } else {
                "Mute microphone"
            }));
        ui.system_panel
            .microphone_device
            .set_text(if s.microphone_device.is_empty() {
                "No input device"
            } else {
                &s.microphone_device
            });
        ui.system_panel
            .microphone_apps
            .set_text(&if s.microphone_apps.is_empty() {
                "No applications are using the microphone".into()
            } else {
                format!("In use by: {}", s.microphone_apps.join(", "))
            });
        let capturing = !s.microphone_apps.is_empty();
        ui.microphone_privacy.set_visible(capturing);
        ui.microphone_privacy
            .set_label(if s.microphone_muted { "󰍭" } else { "󰍬" });
        ui.microphone_privacy.set_tooltip_text(Some(&if capturing {
            format!("Microphone in use by:\n{}", s.microphone_apps.join("\n"))
        } else {
            "Microphone is not in use".into()
        }));
    }
    if matches!(update, ModuleUpdate::Network { .. }) {
        ui.network_icon.set_text(&s.network_icon);
        ui.network_name.set_text(&s.network_name);
        ui.network.set_tooltip_text(Some(&s.network_tooltip));
    }
    if matches!(update, ModuleUpdate::Llm { .. }) {
        ui.llm.set_label(&if s.codex_remaining >= 0 {
            format!(
                "AI {}%{}",
                s.codex_remaining,
                if s.active_llms > 0 {
                    format!(" •{}", s.active_llms)
                } else {
                    String::new()
                }
            )
        } else {
            "AI --".into()
        });
        ui.llm.set_tooltip_text(Some(&format!(
            "Codex quota left: {}%\nResets: {}\nActive clients: {}",
            s.codex_remaining.max(0),
            s.codex_reset,
            s.active_llms
        )));
        ui.llm_detail.set_text(&format!(
            "Codex quota left: {}%\nResets: {}\nTokens today: {}\nActive clients: {}",
            s.codex_remaining.max(0),
            s.codex_reset,
            s.codex_today,
            s.active_llms
        ));
    }
    if matches!(update, ModuleUpdate::Audio { .. }) {
        ui.audio.set_label(&if s.muted {
            "󰖁".into()
        } else {
            format!(
                "{} {}%",
                if s.volume >= 60 {
                    "󰕾"
                } else if s.volume >= 20 {
                    "󰖀"
                } else {
                    "󰕿"
                },
                s.volume
            )
        });
        ui.audio.set_tooltip_text(Some(&if s.muted {
            "Muted · scroll to adjust · right-click for mixer".into()
        } else {
            format!(
                "Volume {}% · scroll to adjust · right-click for mixer",
                s.volume
            )
        }));
    }
    if matches!(
        update,
        ModuleUpdate::Battery { .. } | ModuleUpdate::Profile(_)
    ) {
        let bat_icon = battery_icon(s.battery, &s.battery_status);
        let profile_icon = if s.profile == "power-saver" {
            "󰌪"
        } else if s.profile == "performance" {
            "󰓅"
        } else {
            "󰾅"
        };
        ui.power
            .set_label(&format!("{} {} {}%", profile_icon, bat_icon, s.battery));
        let power_style = ui.power.style_context();
        power_style.remove_class("charging");
        power_style.remove_class("battery-low");
        power_style.remove_class("battery-critical");
        if battery_is_charging(&s.battery_status) {
            power_style.add_class("charging");
        } else if battery_is_discharging(&s.battery_status) && s.battery <= 10 {
            power_style.add_class("battery-critical");
        } else if battery_is_discharging(&s.battery_status) && s.battery <= 20 {
            power_style.add_class("battery-low");
        }
        ui.power.set_tooltip_text(Some(&format!(
            "Battery: {}% · {}\nPower mode: {}\nClick to cycle",
            s.battery, s.battery_status, s.profile
        )));
    }
    if matches!(update, ModuleUpdate::Idle(_)) {
        if s.idle_inhibited {
            ui.idle.set_label("󰅶");
            ui.idle
                .set_tooltip_text(Some("Idle inhibition active · click to allow sleep"));
            ui.idle.style_context().add_class("active");
        } else {
            ui.idle.set_label("󰌽");
            ui.idle
                .set_tooltip_text(Some("Idle inhibition inactive · click to keep awake"));
            ui.idle.style_context().remove_class("active");
        }
    }
    if matches!(update, ModuleUpdate::Bluetooth { .. }) {
        ui.bluetooth.set_label(&if s.bluetooth_count > 0 {
            format!("󰂱 {}", s.bluetooth_count)
        } else if s.bluetooth_powered {
            "󰂯".into()
        } else {
            "󰂲".into()
        });
        ui.bluetooth
            .set_tooltip_text(Some(&if !s.bluetooth_powered {
                "Bluetooth is off".into()
            } else if s.bluetooth_names.is_empty() {
                "Bluetooth on · no connected devices".into()
            } else {
                format!(
                    "Bluetooth · {} connected\n{}",
                    s.bluetooth_count,
                    s.bluetooth_names.join("\n")
                )
            }));
    }
    if matches!(update, ModuleUpdate::Notifications { .. }) {
        ui.notifications.set_label(&if s.dnd {
            "󰂛".into()
        } else if s.notifications > 0 {
            format!("󱅫 {}", s.notifications)
        } else {
            "󰂚".into()
        });
        ui.notifications.set_tooltip_text(Some(&if s.dnd {
            "Do not disturb · right-click to disable".into()
        } else {
            format!("{} notifications · right-click for DND", s.notifications)
        }));
        if s.dnd {
            ui.notifications.style_context().add_class("paused");
        } else {
            ui.notifications.style_context().remove_class("paused");
        }
        if !s.dnd && s.notifications > 0 {
            ui.notifications.style_context().add_class("unread");
        } else {
            ui.notifications.style_context().remove_class("unread");
        }
    }
}

fn schedule_clock(ui: Ui) {
    let now = Local::now();
    let separator = r#"<span font_family="CaskaydiaMono NFP" size="60%"> .</span>"#;
    ui.clock_time.set_markup(&format!(
        "{}{}{}",
        now.format("%H"),
        separator,
        now.format("%M")
    ));
    ui.clock_date.set_markup(&format!(
        "{}{}{}",
        now.format("%m"),
        separator,
        now.format("%d")
    ));
    let delay = Duration::from_secs((60 - now.second() as u64).max(1));
    glib::timeout_add_local_once(delay, move || schedule_clock(ui));
}

fn load_config(path: &Path) -> Result<Config> {
    toml::from_str(&fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?)
        .context("parse config")
}

fn main() -> Result<()> {
    simple_logger::init_with_level(log::Level::Info).ok();
    let async_runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .context("initialize async runtime")?;
    let _async_guard = async_runtime.enter();
    gtk::init().context("initialize GTK")?;
    let args: Vec<String> = std::env::args().collect();
    let path = args
        .windows(2)
        .find(|x| x[0] == "--config")
        .map(|x| PathBuf::from(&x[1]))
        .unwrap_or_else(|| dirs::config_dir().unwrap().join("nixie-shell/config.toml"));
    let config = load_config(&path)?;
    let css_path = path.parent().unwrap().join("style.css");
    let css = gtk::CssProvider::new();
    css.load_from_path(css_path.to_str().context("CSS path")?)
        .context("load CSS")?;
    gtk::StyleContext::add_provider_for_screen(
        &gdk::Screen::default().context("display screen")?,
        &css,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    let metadata = Rc::new(RefCell::new(VecDeque::<NotificationMeta>::with_capacity(
        100,
    )));
    let state = Rc::new(RefCell::new(Snapshot::default()));
    let (update_tx, update_rx) = glib::MainContext::channel(glib::Priority::default());
    let (meta_tx, meta_rx) = glib::MainContext::channel(glib::Priority::default());
    let (input_tx, input_rx) = glib::MainContext::channel(glib::Priority::default());
    monitor_input(input_tx);
    let (win, ui) = build_bar(&config, metadata.clone(), update_tx.clone());
    let _divergence = divergence::start(
        config.divergence.enabled,
        &config.divergence.monitors,
        config.divergence.roll_fps,
    );
    let (candidate_win, candidate_root) = create_candidate_window();
    let meta_ref = metadata.clone();
    let meta_ui = ui.clone();
    let alert_state = state.clone();
    let alert_updates = update_tx.clone();
    let alert_generations = Rc::new((0..10).map(|_| Cell::new(0u64)).collect::<Vec<_>>());
    let meta_generations = alert_generations.clone();
    meta_rx.attach(None, move |meta: NotificationMeta| {
        if let Some(workspace) = meta
            .workspace
            .filter(|workspace| *workspace != alert_state.borrow().workspace)
        {
            if let Some(generation) = meta_generations.get((workspace - 1).max(0) as usize) {
                let token = generation.get().wrapping_add(1);
                generation.set(token);
                let _ = alert_updates.send(ModuleUpdate::WorkspaceAlert {
                    workspace,
                    active: true,
                });
                for (delay, active) in [
                    (180, false),
                    (360, true),
                    (540, false),
                    (720, true),
                    (900, false),
                    (1080, true),
                ] {
                    let generations = meta_generations.clone();
                    let updates = alert_updates.clone();
                    glib::timeout_add_local_once(Duration::from_millis(delay), move || {
                        if generations
                            .get((workspace - 1) as usize)
                            .is_some_and(|value| value.get() == token)
                        {
                            let _ = updates
                                .send(ModuleUpdate::WorkspaceAlertPulse { workspace, active });
                        }
                    });
                }
            }
        }
        let mut values = meta_ref.borrow_mut();
        values.push_back(meta);
        while values.len() > 100 {
            values.pop_front();
        }
        meta_ui.notifications.set_label("󱅫");
        meta_ui.notifications.style_context().add_class("unread");
        meta_ui
            .notifications
            .set_tooltip_text(Some("New notification · click for notification center"));
        glib::Continue(true)
    });
    let input_ui = ui.clone();
    input_rx.attach(None, move |value| {
        match value {
            FcitxMessage::Status {
                active,
                name,
                label,
            } => {
                input_ui.input.set_label(&label);
                input_ui.input.set_tooltip_text(Some(&format!(
                    "Input method: {}{}",
                    name,
                    if active { "" } else { " (direct)" }
                )));
            }
            candidates @ FcitxMessage::Candidates { .. } => {
                update_candidates(&candidate_win, &candidate_root, candidates)
            }
        };
        glib::Continue(true)
    });
    let update_ui_ref = ui.clone();
    let update_state = state.clone();
    let update_generations = alert_generations.clone();
    update_rx.attach(None, move |value| {
        let mut current = update_state.borrow_mut();
        let render = value.clone();
        value.apply(&mut current);
        if let ModuleUpdate::Workspace(workspace) = &render {
            if current.workspace_alerts.len() < 10 {
                current.workspace_alerts.resize(10, false);
            }
            if current.workspace_alert_pulses.len() < 10 {
                current.workspace_alert_pulses.resize(10, false);
            }
            if let Some(alert) = current
                .workspace_alerts
                .get_mut((*workspace - 1).max(0) as usize)
            {
                *alert = false;
            }
            if let Some(pulse) = current
                .workspace_alert_pulses
                .get_mut((*workspace - 1).max(0) as usize)
            {
                *pulse = false;
            }
            if let Some(generation) = update_generations.get((*workspace - 1).max(0) as usize) {
                generation.set(generation.get().wrapping_add(1));
            }
        } else if matches!(render, ModuleUpdate::ClearWorkspaceAlerts) {
            for generation in update_generations.iter() {
                generation.set(generation.get().wrapping_add(1));
            }
        }
        update_ui(&update_ui_ref, &current, &render);
        glib::Continue(true)
    });
    schedule_clock(ui.clone());
    monitor_notifications(meta_tx, update_tx.clone());
    events::start_workspace(update_tx.clone());
    events::start_audio(update_tx.clone());
    events::start_brightness(update_tx.clone());
    events::start_metrics(update_tx.clone(), config.refresh.metrics_seconds);
    events::start_llm(update_tx.clone(), config.refresh.llm_seconds);
    events::start_reconcile(update_tx.clone(), config.refresh.reconcile_seconds);
    events::start_dbus(update_tx, config.refresh.event_coalesce_ms);
    win.connect_destroy(|_| gtk::main_quit());
    win.show_all();
    gtk::main();
    Ok(())
}
