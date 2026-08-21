use chrono::{
    DateTime, Datelike, Duration as ChronoDuration, Local, LocalResult, Months, NaiveDate,
    NaiveDateTime, TimeZone, Utc, Weekday,
};
use gtk::gdk;
use gtk::prelude::*;
use gtk_layer_shell::{self as layer_shell, Edge, KeyboardMode, Layer};
use serde::{Deserialize, Serialize};
use std::cell::RefCell;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const GOOGLE_CALENDAR_SETTINGS: &str = "https://calendar.google.com/calendar/u/0/r/settings";

#[derive(Clone, Debug, Deserialize, Serialize)]
struct TodoItem {
    id: u64,
    text: String,
    done: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct CalendarEvent {
    summary: String,
    start: DateTime<Local>,
    end: DateTime<Local>,
    all_day: bool,
    location: String,
    url: String,
}

#[derive(Default)]
struct EventSeed {
    summary: String,
    start: Option<DateTime<Local>>,
    end: Option<DateTime<Local>>,
    all_day: bool,
    location: String,
    url: String,
    status: String,
    rrule: String,
    exdates: Vec<DateTime<Local>>,
}

enum CalendarUpdate {
    Loading,
    Events(Vec<CalendarEvent>),
    Error(String),
    Disconnected,
}

pub struct DesktopManager {
    _window: gtk::Window,
}

fn data_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("nixie-shell")
}

fn todo_path() -> PathBuf {
    data_dir().join("todos.json")
}

fn calendar_secret_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("nixie-shell/google-calendar-url")
}

fn atomic_private_write(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension("tmp");
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)?;
    file.write_all(contents)?;
    file.sync_all()?;
    fs::rename(temporary, path)
}

fn load_todos() -> Vec<TodoItem> {
    fs::read_to_string(todo_path())
        .ok()
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_default()
}

fn save_todos(todos: &[TodoItem]) {
    if let Ok(value) = serde_json::to_vec_pretty(todos) {
        if let Err(error) = atomic_private_write(&todo_path(), &value) {
            log::warn!("save desktop todos: {error}");
        }
    }
}

fn next_todo_id() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64
}

fn clear_container(container: &gtk::Container) {
    for child in container.children() {
        container.remove(&child);
    }
}

fn render_todos(list: &gtk::ListBox, summary: &gtk::Label, todos: &Rc<RefCell<Vec<TodoItem>>>) {
    clear_container(list.upcast_ref());
    let values = todos.borrow().clone();
    let remaining = values.iter().filter(|todo| !todo.done).count();
    summary.set_label(&format!("{remaining} remaining · {} total", values.len()));

    if values.is_empty() {
        let empty = gtk::Label::new(Some("Nothing pending — enjoy the quiet."));
        empty.set_xalign(0.0);
        empty.style_context().add_class("desktop-empty");
        list.add(&empty);
    }

    for todo in values {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        row.style_context().add_class("todo-row");
        let check = gtk::CheckButton::with_label(&todo.text);
        check.set_active(todo.done);
        check.set_hexpand(true);
        check.set_halign(gtk::Align::Fill);
        if todo.done {
            check.style_context().add_class("done");
        }
        let remove = gtk::Button::with_label("󰆴");
        remove.style_context().add_class("todo-remove");
        remove.set_tooltip_text(Some("Delete todo"));
        row.pack_start(&check, true, true, 0);
        row.pack_end(&remove, false, false, 0);
        list.add(&row);

        let id = todo.id;
        let toggle_values = todos.clone();
        let toggle_list = list.clone();
        let toggle_summary = summary.clone();
        check.connect_toggled(move |button| {
            if let Some(value) = toggle_values
                .borrow_mut()
                .iter_mut()
                .find(|value| value.id == id)
            {
                value.done = button.is_active();
            }
            save_todos(&toggle_values.borrow());
            render_todos(&toggle_list, &toggle_summary, &toggle_values);
        });

        let remove_values = todos.clone();
        let remove_list = list.clone();
        let remove_summary = summary.clone();
        remove.connect_clicked(move |_| {
            remove_values.borrow_mut().retain(|value| value.id != id);
            save_todos(&remove_values.borrow());
            render_todos(&remove_list, &remove_summary, &remove_values);
        });
    }
    list.show_all();
}

fn add_todo(
    entry: &gtk::Entry,
    list: &gtk::ListBox,
    summary: &gtk::Label,
    todos: &Rc<RefCell<Vec<TodoItem>>>,
) {
    let text = entry.text().trim().to_string();
    if text.is_empty() {
        return;
    }
    todos.borrow_mut().push(TodoItem {
        id: next_todo_id(),
        text,
        done: false,
    });
    save_todos(&todos.borrow());
    entry.set_text("");
    render_todos(list, summary, todos);
}

fn local_datetime(date: NaiveDate, time: chrono::NaiveTime) -> Option<DateTime<Local>> {
    match Local.from_local_datetime(&date.and_time(time)) {
        LocalResult::Single(value) | LocalResult::Ambiguous(value, _) => Some(value),
        LocalResult::None => None,
    }
}

fn parse_ical_datetime(value: &str, date_only: bool) -> Option<DateTime<Local>> {
    if date_only || value.len() == 8 {
        let date = NaiveDate::parse_from_str(value, "%Y%m%d").ok()?;
        return local_datetime(date, chrono::NaiveTime::MIN);
    }
    if let Some(value) = value.strip_suffix('Z') {
        let naive = NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%S").ok()?;
        return Some(Utc.from_utc_datetime(&naive).with_timezone(&Local));
    }
    let naive = NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%S").ok()?;
    match Local.from_local_datetime(&naive) {
        LocalResult::Single(value) | LocalResult::Ambiguous(value, _) => Some(value),
        LocalResult::None => None,
    }
}

fn unescape_ical(value: &str) -> String {
    value
        .replace("\\n", "\n")
        .replace("\\N", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
}

fn unfold_ical(input: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for raw in input.replace("\r\n", "\n").split('\n') {
        if (raw.starts_with(' ') || raw.starts_with('\t')) && !lines.is_empty() {
            lines.last_mut().unwrap().push_str(&raw[1..]);
        } else {
            lines.push(raw.trim_end_matches('\r').to_string());
        }
    }
    lines
}

fn property(line: &str) -> (&str, &str, &str) {
    let (head, value) = line.split_once(':').unwrap_or((line, ""));
    let (name, parameters) = head.split_once(';').unwrap_or((head, ""));
    (name, parameters, value)
}

fn weekday(value: &str) -> Option<Weekday> {
    match value.trim_start_matches(|ch: char| ch == '+' || ch == '-' || ch.is_ascii_digit()) {
        "MO" => Some(Weekday::Mon),
        "TU" => Some(Weekday::Tue),
        "WE" => Some(Weekday::Wed),
        "TH" => Some(Weekday::Thu),
        "FR" => Some(Weekday::Fri),
        "SA" => Some(Weekday::Sat),
        "SU" => Some(Weekday::Sun),
        _ => None,
    }
}

fn occurrence(seed: &EventSeed, start: DateTime<Local>) -> CalendarEvent {
    let duration = seed
        .end
        .zip(seed.start)
        .map(|(end, start)| end - start)
        .unwrap_or_else(|| {
            if seed.all_day {
                ChronoDuration::days(1)
            } else {
                ChronoDuration::hours(1)
            }
        });
    CalendarEvent {
        summary: seed.summary.clone(),
        start,
        end: start + duration,
        all_day: seed.all_day,
        location: seed.location.clone(),
        url: seed.url.clone(),
    }
}

fn add_if_visible(
    values: &mut Vec<CalendarEvent>,
    seed: &EventSeed,
    start: DateTime<Local>,
    from: DateTime<Local>,
    until: DateTime<Local>,
) {
    if seed
        .exdates
        .iter()
        .any(|excluded| excluded.timestamp() == start.timestamp())
    {
        return;
    }
    let value = occurrence(seed, start);
    if value.end >= from && value.start <= until {
        values.push(value);
    }
}

fn expand_seed(
    seed: &EventSeed,
    from: DateTime<Local>,
    until: DateTime<Local>,
) -> Vec<CalendarEvent> {
    let Some(start) = seed.start else {
        return Vec::new();
    };
    if seed.status.eq_ignore_ascii_case("CANCELLED") {
        return Vec::new();
    }
    if seed.rrule.is_empty() {
        let mut values = Vec::new();
        add_if_visible(&mut values, seed, start, from, until);
        return values;
    }

    let rules: std::collections::HashMap<&str, &str> = seed
        .rrule
        .split(';')
        .filter_map(|value| value.split_once('='))
        .collect();
    let frequency = rules.get("FREQ").copied().unwrap_or("");
    let interval = rules
        .get("INTERVAL")
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(1)
        .max(1);
    let count = rules
        .get("COUNT")
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(usize::MAX);
    let rule_until = rules
        .get("UNTIL")
        .and_then(|value| parse_ical_datetime(value, value.len() == 8));
    let mut values = Vec::new();
    let mut generated = 0usize;

    if frequency == "WEEKLY" && rules.contains_key("BYDAY") {
        let days: Vec<Weekday> = rules["BYDAY"].split(',').filter_map(weekday).collect();
        let week_start = start.date_naive()
            - ChronoDuration::days(start.weekday().num_days_from_monday() as i64);
        for week in 0..520u32 {
            let base = week_start + ChronoDuration::weeks((week * interval) as i64);
            for day in &days {
                let date = base + ChronoDuration::days(day.num_days_from_monday() as i64);
                let Some(candidate) = local_datetime(date, start.time()) else {
                    continue;
                };
                if candidate < start {
                    continue;
                }
                if generated >= count || rule_until.is_some_and(|limit| candidate > limit) {
                    return values;
                }
                generated += 1;
                if candidate > until {
                    return values;
                }
                add_if_visible(&mut values, seed, candidate, from, until);
            }
        }
        return values;
    }

    for index in 0..1000u32 {
        let candidate = match frequency {
            "DAILY" => start.checked_add_signed(ChronoDuration::days((index * interval) as i64)),
            "WEEKLY" => start.checked_add_signed(ChronoDuration::weeks((index * interval) as i64)),
            "MONTHLY" => start.checked_add_months(Months::new(index * interval)),
            "YEARLY" => start.checked_add_months(Months::new(index * interval * 12)),
            _ if index == 0 => Some(start),
            _ => None,
        };
        let Some(candidate) = candidate else {
            break;
        };
        if generated >= count
            || rule_until.is_some_and(|limit| candidate > limit)
            || candidate > until
        {
            break;
        }
        generated += 1;
        add_if_visible(&mut values, seed, candidate, from, until);
    }
    values
}

fn parse_calendar(input: &str, now: DateTime<Local>) -> Vec<CalendarEvent> {
    let mut seeds = Vec::new();
    let mut current: Option<EventSeed> = None;
    for line in unfold_ical(input) {
        if line == "BEGIN:VEVENT" {
            current = Some(EventSeed::default());
            continue;
        }
        if line == "END:VEVENT" {
            if let Some(seed) = current.take() {
                seeds.push(seed);
            }
            continue;
        }
        let Some(seed) = current.as_mut() else {
            continue;
        };
        let (name, parameters, value) = property(&line);
        match name {
            "SUMMARY" => seed.summary = unescape_ical(value),
            "LOCATION" => seed.location = unescape_ical(value),
            "URL" => seed.url = value.to_string(),
            "STATUS" => seed.status = value.to_string(),
            "RRULE" => seed.rrule = value.to_string(),
            "DTSTART" => {
                seed.all_day = parameters.contains("VALUE=DATE") || value.len() == 8;
                seed.start = parse_ical_datetime(value, seed.all_day);
            }
            "DTEND" => {
                seed.end = parse_ical_datetime(
                    value,
                    parameters.contains("VALUE=DATE") || value.len() == 8,
                )
            }
            "EXDATE" => {
                let date_only = parameters.contains("VALUE=DATE");
                seed.exdates.extend(
                    value
                        .split(',')
                        .filter_map(|value| parse_ical_datetime(value, date_only)),
                );
            }
            _ => {}
        }
    }

    let from = now - ChronoDuration::hours(12);
    let until = now + ChronoDuration::days(14);
    let mut values: Vec<CalendarEvent> = seeds
        .iter()
        .flat_map(|seed| expand_seed(seed, from, until))
        .collect();
    values.sort_by_key(|value| value.start);
    values.dedup_by(|left, right| {
        left.start.timestamp() == right.start.timestamp() && left.summary == right.summary
    });
    values.truncate(8);
    values
}

fn calendar_url() -> Option<String> {
    fs::read_to_string(calendar_secret_path())
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn valid_calendar_url(value: &str) -> bool {
    value.starts_with("https://")
        && value.contains("calendar.google.com/")
        && value.ends_with(".ics")
        && !value.chars().any(char::is_control)
        && !value.contains(['"', '\\'])
}

fn fetch_calendar(sender: glib::Sender<CalendarUpdate>) {
    let _ = sender.send(CalendarUpdate::Loading);
    thread::spawn(move || {
        let Some(url) = calendar_url() else {
            let _ = sender.send(CalendarUpdate::Disconnected);
            return;
        };
        let result = Command::new("curl")
            .args([
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--max-time",
                "20",
                "--config",
                "-",
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .and_then(|mut child| {
                if let Some(mut input) = child.stdin.take() {
                    writeln!(input, "url = \"{url}\"")?;
                }
                child.wait_with_output()
            });
        match result {
            Ok(output) if output.status.success() => {
                let input = String::from_utf8_lossy(&output.stdout);
                let _ = sender.send(CalendarUpdate::Events(parse_calendar(&input, Local::now())));
            }
            Ok(output) => {
                let _ = sender.send(CalendarUpdate::Error(format!(
                    "Request failed ({})",
                    output.status
                )));
            }
            Err(error) => {
                let _ = sender.send(CalendarUpdate::Error(error.to_string()));
            }
        }
    });
}

fn format_event_time(event: &CalendarEvent, now: DateTime<Local>) -> String {
    let date = event.start.date_naive();
    let prefix = if date == now.date_naive() {
        "Today".to_string()
    } else if date == (now + ChronoDuration::days(1)).date_naive() {
        "Tomorrow".to_string()
    } else {
        event.start.format("%a %m/%d").to_string()
    };
    if event.all_day {
        format!("{prefix} · All day")
    } else {
        format!("{prefix} · {}", event.start.format("%H:%M"))
    }
}

fn render_events(container: &gtk::Box, events: &[CalendarEvent]) {
    clear_container(container.upcast_ref());
    if events.is_empty() {
        let empty = gtk::Label::new(Some("No events in the next two weeks."));
        empty.set_xalign(0.0);
        empty.style_context().add_class("desktop-empty");
        container.pack_start(&empty, false, false, 0);
    }
    let now = Local::now();
    for event in events {
        let button = gtk::Button::new();
        button.style_context().add_class("calendar-event");
        let row = gtk::Box::new(gtk::Orientation::Vertical, 2);
        let title = gtk::Label::new(Some(&event.summary));
        title.set_xalign(0.0);
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let time = gtk::Label::new(Some(&format_event_time(event, now)));
        time.set_xalign(0.0);
        time.style_context().add_class("calendar-event-time");
        row.pack_start(&title, false, false, 0);
        row.pack_start(&time, false, false, 0);
        button.add(&row);
        let target = if event.url.is_empty() {
            GOOGLE_CALENDAR_SETTINGS.to_string()
        } else {
            event.url.clone()
        };
        button.connect_clicked(move |_| crate::telemetry::spawn("xdg-open", &[&target]));
        if !event.location.is_empty() {
            button.set_tooltip_text(Some(&event.location));
        }
        container.pack_start(&button, false, false, 0);
    }
    container.show_all();
}

pub fn start(enabled: bool, monitor_index: i32, refresh_minutes: u64) -> Option<DesktopManager> {
    if !enabled {
        return None;
    }
    let window = gtk::Window::new(gtk::WindowType::Toplevel);
    window.set_widget_name("nixie-desktop");
    window.style_context().add_class("nixie-desktop");
    window.set_app_paintable(true);
    window.set_decorated(false);
    window.set_resizable(false);
    window.set_default_size(380, -1);
    if let Some(screen) = gtk::prelude::WidgetExt::screen(&window) {
        if let Some(visual) = screen.rgba_visual() {
            window.set_visual(Some(&visual));
        }
    }
    layer_shell::init_for_window(&window);
    layer_shell::set_namespace(&window, "nixie-desktop");
    layer_shell::set_layer(&window, Layer::Bottom);
    layer_shell::set_anchor(&window, Edge::Top, true);
    layer_shell::set_anchor(&window, Edge::Right, true);
    layer_shell::set_margin(&window, Edge::Top, 72);
    layer_shell::set_margin(&window, Edge::Right, 24);
    layer_shell::set_exclusive_zone(&window, -1);
    layer_shell::set_keyboard_mode(&window, KeyboardMode::OnDemand);
    if let Some(display) = gdk::Display::default() {
        if let Some(monitor) = display.monitor(monitor_index.max(0)) {
            layer_shell::set_monitor(&window, &monitor);
        }
    }

    let root = gtk::Box::new(gtk::Orientation::Vertical, 12);
    root.style_context().add_class("desktop-card");

    let todo_header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let todo_title = gtk::Label::new(Some("󰄲  TODO"));
    todo_title.style_context().add_class("desktop-title");
    todo_title.set_xalign(0.0);
    let todo_summary = gtk::Label::new(None);
    todo_summary.style_context().add_class("desktop-summary");
    todo_summary.set_xalign(1.0);
    todo_header.pack_start(&todo_title, true, true, 0);
    todo_header.pack_end(&todo_summary, false, false, 0);
    root.pack_start(&todo_header, false, false, 0);

    let add_row = gtk::Box::new(gtk::Orientation::Horizontal, 7);
    let entry = gtk::Entry::new();
    entry.set_placeholder_text(Some("Add a task…"));
    entry.style_context().add_class("todo-entry");
    let add = gtk::Button::with_label("＋");
    add.style_context().add_class("todo-add");
    add_row.pack_start(&entry, true, true, 0);
    add_row.pack_end(&add, false, false, 0);
    root.pack_start(&add_row, false, false, 0);

    let scroll = gtk::ScrolledWindow::new(None::<&gtk::Adjustment>, None::<&gtk::Adjustment>);
    scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scroll.set_min_content_height(130);
    scroll.set_max_content_height(260);
    scroll.set_propagate_natural_height(true);
    let todo_list = gtk::ListBox::new();
    todo_list.set_selection_mode(gtk::SelectionMode::None);
    scroll.add(&todo_list);
    root.pack_start(&scroll, false, false, 0);

    let todos = Rc::new(RefCell::new(load_todos()));
    render_todos(&todo_list, &todo_summary, &todos);
    let activate_list = todo_list.clone();
    let activate_summary = todo_summary.clone();
    let activate_todos = todos.clone();
    entry.connect_activate(move |entry| {
        add_todo(entry, &activate_list, &activate_summary, &activate_todos)
    });
    let add_entry = entry.clone();
    let add_list = todo_list.clone();
    let add_summary = todo_summary.clone();
    let add_todos = todos.clone();
    add.connect_clicked(move |_| add_todo(&add_entry, &add_list, &add_summary, &add_todos));

    let separator = gtk::Separator::new(gtk::Orientation::Horizontal);
    separator.style_context().add_class("desktop-separator");
    root.pack_start(&separator, false, false, 0);

    let calendar_header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let calendar_title = gtk::Label::new(Some("󰃭  UPCOMING"));
    calendar_title.style_context().add_class("desktop-title");
    calendar_title.set_xalign(0.0);
    let refresh = gtk::Button::with_label("󰑐");
    refresh.style_context().add_class("calendar-refresh");
    refresh.set_tooltip_text(Some("Refresh Google Calendar"));
    calendar_header.pack_start(&calendar_title, true, true, 0);
    calendar_header.pack_end(&refresh, false, false, 0);
    root.pack_start(&calendar_header, false, false, 0);

    let calendar_status = gtk::Label::new(Some("Calendar not connected"));
    calendar_status.set_xalign(0.0);
    calendar_status.style_context().add_class("calendar-status");
    root.pack_start(&calendar_status, false, false, 0);

    let setup = gtk::Box::new(gtk::Orientation::Vertical, 7);
    setup.style_context().add_class("calendar-setup");
    let setup_help = gtk::Label::new(Some(
        "Google Calendar → Settings → Integrate calendar → Secret address in iCal format",
    ));
    setup_help.set_xalign(0.0);
    setup_help.set_line_wrap(true);
    let secret_entry = gtk::Entry::new();
    secret_entry.set_placeholder_text(Some("Paste the secret .ics address"));
    secret_entry.set_visibility(false);
    let setup_actions = gtk::Box::new(gtk::Orientation::Horizontal, 7);
    let open_settings = gtk::Button::with_label("Open Google settings");
    let connect = gtk::Button::with_label("Connect");
    setup_actions.pack_start(&open_settings, true, true, 0);
    setup_actions.pack_end(&connect, false, false, 0);
    setup.pack_start(&setup_help, false, false, 0);
    setup.pack_start(&secret_entry, false, false, 0);
    setup.pack_start(&setup_actions, false, false, 0);
    root.pack_start(&setup, false, false, 0);

    let connected_actions = gtk::Box::new(gtk::Orientation::Horizontal, 7);
    let disconnect = gtk::Button::with_label("Disconnect calendar");
    disconnect.style_context().add_class("calendar-disconnect");
    connected_actions.pack_end(&disconnect, false, false, 0);
    root.pack_start(&connected_actions, false, false, 0);

    let events_box = gtk::Box::new(gtk::Orientation::Vertical, 5);
    root.pack_start(&events_box, false, false, 0);
    window.add(&root);
    window.show_all();

    let connected = calendar_url().is_some();
    setup.set_visible(!connected);
    connected_actions.set_visible(connected);
    events_box.set_visible(connected);
    refresh.set_sensitive(connected);

    let (calendar_tx, calendar_rx) = glib::MainContext::channel(glib::Priority::default());
    let status_ref = calendar_status.clone();
    let events_ref = events_box.clone();
    let setup_ref = setup.clone();
    let connected_ref = connected_actions.clone();
    let refresh_ref = refresh.clone();
    calendar_rx.attach(None, move |update| {
        match update {
            CalendarUpdate::Loading => status_ref.set_label("Syncing Google Calendar…"),
            CalendarUpdate::Events(events) => {
                status_ref.set_label(&format!(
                    "Google Calendar · {} · {} events",
                    Local::now().format("%H:%M"),
                    events.len()
                ));
                setup_ref.hide();
                connected_ref.show();
                events_ref.show();
                refresh_ref.set_sensitive(true);
                render_events(&events_ref, &events);
            }
            CalendarUpdate::Error(error) => {
                status_ref.set_label(&format!("Calendar error · {error}"));
            }
            CalendarUpdate::Disconnected => {
                status_ref.set_label("Calendar not connected");
                setup_ref.show();
                connected_ref.hide();
                events_ref.hide();
                refresh_ref.set_sensitive(false);
            }
        }
        glib::Continue(true)
    });

    open_settings
        .connect_clicked(|_| crate::telemetry::spawn("xdg-open", &[GOOGLE_CALENDAR_SETTINGS]));
    let connect_tx = calendar_tx.clone();
    let connect_status = calendar_status.clone();
    let connect_entry = secret_entry.clone();
    connect.connect_clicked(move |_| {
        let value = connect_entry.text().trim().to_string();
        if !valid_calendar_url(&value) {
            connect_status.set_label("Use Google’s HTTPS Secret address ending in .ics");
            return;
        }
        match atomic_private_write(&calendar_secret_path(), value.as_bytes()) {
            Ok(()) => {
                connect_entry.set_text("");
                fetch_calendar(connect_tx.clone());
            }
            Err(error) => {
                connect_status.set_label(&format!("Cannot save calendar secret · {error}"))
            }
        }
    });
    let refresh_tx = calendar_tx.clone();
    refresh.connect_clicked(move |_| fetch_calendar(refresh_tx.clone()));
    let disconnect_tx = calendar_tx.clone();
    disconnect.connect_clicked(move |_| {
        match fs::remove_file(calendar_secret_path()) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                let _ = disconnect_tx.send(CalendarUpdate::Error(error.to_string()));
                return;
            }
        }
        let _ = disconnect_tx.send(CalendarUpdate::Disconnected);
    });

    fetch_calendar(calendar_tx.clone());
    thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(refresh_minutes.max(1) * 60));
        fetch_calendar(calendar_tx.clone());
    });

    Some(DesktopManager { _window: window })
}

#[cfg(test)]
mod tests {
    use super::{atomic_private_write, parse_calendar, valid_calendar_url};
    use chrono::{Datelike, Local, TimeZone};
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn accepts_only_google_https_ical_secrets() {
        assert!(valid_calendar_url(
            "https://calendar.google.com/calendar/ical/user/private-token/basic.ics"
        ));
        assert!(!valid_calendar_url("http://calendar.google.com/basic.ics"));
        assert!(!valid_calendar_url("https://example.com/basic.ics"));
        assert!(!valid_calendar_url(
            "https://calendar.google.com/calendar/ical/\"bad/basic.ics"
        ));
    }

    #[test]
    fn calendar_secrets_are_written_private() {
        let path =
            std::env::temp_dir().join(format!("nixie-calendar-secret-test-{}", std::process::id()));
        atomic_private_write(&path, b"secret").unwrap();
        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn parses_and_expands_weekly_events() {
        let input = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Research\\, sync\r\nDTSTART;TZID=Asia/Taipei:20260817T100000\r\nDTEND;TZID=Asia/Taipei:20260817T110000\r\nRRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        let now = Local
            .with_ymd_and_hms(2026, 8, 17, 9, 0, 0)
            .single()
            .unwrap();
        let values = parse_calendar(input, now);
        assert_eq!(values.len(), 4);
        assert_eq!(values[0].summary, "Research, sync");
        assert_eq!(values[1].start.day(), 19);
    }
}
