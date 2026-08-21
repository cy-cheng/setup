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
use std::time::{SystemTime, UNIX_EPOCH};

const GOOGLE_CALENDAR_SETTINGS: &str = "https://calendar.google.com/calendar/u/0/r/settings";
const CALENDAR_COLOR_COUNT: u8 = 6;
const CALENDAR_WEEKS: i64 = 4;
const VISIBLE_EVENTS_PER_DAY: usize = 2;

#[derive(Clone, Debug, Deserialize, Serialize)]
struct TodoItem {
    id: u64,
    text: String,
    done: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct CalendarEvent {
    calendar: String,
    color: u8,
    summary: String,
    start: DateTime<Local>,
    end: DateTime<Local>,
    all_day: bool,
    location: String,
    url: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct CalendarFeed {
    id: u64,
    name: String,
    url: String,
    #[serde(default)]
    color: Option<u8>,
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
    Loading(NaiveDate),
    Events {
        period_start: NaiveDate,
        events: Vec<CalendarEvent>,
        feeds: Vec<CalendarFeed>,
        failed: Vec<String>,
    },
    Error(String),
    Disconnected(NaiveDate),
}

pub struct DesktopManager {
    _todo_window: gtk::Window,
    _calendar_window: gtk::Window,
}

fn data_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("nixie-shell")
}

fn todo_path() -> PathBuf {
    data_dir().join("todos.json")
}

fn calendar_feeds_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("nixie-shell/google-calendars.json")
}

fn legacy_calendar_secret_path() -> PathBuf {
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
        calendar: String::new(),
        color: 0,
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

fn parse_calendar_range(
    input: &str,
    from: DateTime<Local>,
    until: DateTime<Local>,
) -> Vec<CalendarEvent> {
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

    let mut values: Vec<CalendarEvent> = seeds
        .iter()
        .flat_map(|seed| expand_seed(seed, from, until))
        .collect();
    values.sort_by_key(|value| value.start);
    values.dedup_by(|left, right| {
        left.start.timestamp() == right.start.timestamp() && left.summary == right.summary
    });
    values
}

#[cfg(test)]
fn parse_calendar(input: &str, now: DateTime<Local>) -> Vec<CalendarEvent> {
    parse_calendar_range(
        input,
        now - ChronoDuration::hours(12),
        now + ChronoDuration::days(14),
    )
}

fn week_start(date: NaiveDate) -> NaiveDate {
    date - ChronoDuration::days(date.weekday().num_days_from_monday() as i64)
}

fn shift_period(start: NaiveDate, direction: i64) -> NaiveDate {
    week_start(start)
        .checked_add_signed(ChronoDuration::weeks(direction * CALENDAR_WEEKS))
        .unwrap_or(start)
}

fn period_bounds(start: NaiveDate) -> (NaiveDate, NaiveDate) {
    let first = week_start(start);
    (first, first + ChronoDuration::days(CALENDAR_WEEKS * 7 - 1))
}

fn period_datetime_bounds(start: NaiveDate) -> Option<(DateTime<Local>, DateTime<Local>)> {
    let (first, last) = period_bounds(start);
    Some((
        local_datetime(first, chrono::NaiveTime::MIN)?,
        local_datetime(
            last.checked_add_signed(ChronoDuration::days(1))?,
            chrono::NaiveTime::MIN,
        )?,
    ))
}

fn event_occurs_on(event: &CalendarEvent, date: NaiveDate) -> bool {
    let Some(start) = local_datetime(date, chrono::NaiveTime::MIN) else {
        return false;
    };
    let Some(next) = date
        .checked_add_signed(ChronoDuration::days(1))
        .and_then(|value| local_datetime(value, chrono::NaiveTime::MIN))
    else {
        return false;
    };
    event.start < next && event.end > start
}

fn load_calendar_feeds() -> Vec<CalendarFeed> {
    if let Some(mut feeds) = fs::read_to_string(calendar_feeds_path())
        .ok()
        .and_then(|value| serde_json::from_str::<Vec<CalendarFeed>>(&value).ok())
    {
        if normalize_feed_colors(&mut feeds) {
            if let Err(error) = save_calendar_feeds(&feeds) {
                log::warn!("save calendar colors: {error}");
            }
        }
        let legacy_path = legacy_calendar_secret_path();
        if legacy_path.exists() {
            if let Err(error) = fs::remove_file(legacy_path) {
                log::warn!("remove migrated calendar secret: {error}");
            }
        }
        return feeds;
    }
    let legacy_path = legacy_calendar_secret_path();
    let feeds = fs::read_to_string(&legacy_path)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| valid_calendar_url(value))
        .map(|url| {
            vec![CalendarFeed {
                id: 1,
                name: "Google Calendar".into(),
                url,
                color: Some(0),
            }]
        })
        .unwrap_or_default();
    if !feeds.is_empty() {
        match save_calendar_feeds(&feeds) {
            Ok(()) => {
                if let Err(error) = fs::remove_file(&legacy_path) {
                    log::warn!("remove migrated calendar secret: {error}");
                }
            }
            Err(error) => log::warn!("migrate calendar secret: {error}"),
        }
    }
    feeds
}

fn normalize_feed_colors(feeds: &mut [CalendarFeed]) -> bool {
    let mut changed = false;
    for (index, feed) in feeds.iter_mut().enumerate() {
        if feed.color.is_none_or(|color| color >= CALENDAR_COLOR_COUNT) {
            feed.color = Some((index as u8) % CALENDAR_COLOR_COUNT);
            changed = true;
        }
    }
    changed
}

fn save_calendar_feeds(feeds: &[CalendarFeed]) -> std::io::Result<()> {
    let value = serde_json::to_vec_pretty(feeds)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    atomic_private_write(&calendar_feeds_path(), &value)
}

fn valid_calendar_url(value: &str) -> bool {
    value.starts_with("https://")
        && value.len() > "https://".len()
        && !value.chars().any(char::is_control)
        && !value.contains(['"', '\\'])
}

fn fetch_ical(url: &str) -> std::io::Result<std::process::Output> {
    Command::new("curl")
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
        })
}

fn fetch_calendar(sender: glib::Sender<CalendarUpdate>, period_start: NaiveDate) {
    let period_start = week_start(period_start);
    let _ = sender.send(CalendarUpdate::Loading(period_start));
    thread::spawn(move || {
        let feeds = load_calendar_feeds();
        if feeds.is_empty() {
            let _ = sender.send(CalendarUpdate::Disconnected(period_start));
            return;
        }
        let Some((from, until)) = period_datetime_bounds(period_start) else {
            let _ = sender.send(CalendarUpdate::Error("Invalid calendar period".into()));
            return;
        };
        let mut events = Vec::new();
        let mut failed = Vec::new();
        let requests: Vec<_> = feeds
            .iter()
            .cloned()
            .map(|feed| thread::spawn(move || (fetch_ical(&feed.url), feed)))
            .collect();
        for request in requests {
            let Ok((result, feed)) = request.join() else {
                continue;
            };
            match result {
                Ok(output) if output.status.success() => {
                    let input = String::from_utf8_lossy(&output.stdout);
                    let mut values = parse_calendar_range(&input, from, until);
                    for event in &mut values {
                        event.calendar.clone_from(&feed.name);
                        event.color = feed.color.unwrap_or(0) % CALENDAR_COLOR_COUNT;
                    }
                    events.extend(values);
                }
                _ => failed.push(feed.name.clone()),
            }
        }
        events.sort_by_key(|event| event.start);
        let _ = sender.send(CalendarUpdate::Events {
            period_start,
            events,
            feeds,
            failed,
        });
    });
}

fn format_event_details(event: &CalendarEvent) -> String {
    if event.all_day {
        format!("{} · All day", event.start.format("%A, %B %-d"))
    } else {
        format!(
            "{} · {}–{}",
            event.start.format("%A, %B %-d"),
            event.start.format("%H:%M"),
            event.end.format("%H:%M")
        )
    }
}

fn color_class(color: u8) -> String {
    format!("calendar-color-{}", color % CALENDAR_COLOR_COUNT)
}

fn calendar_event_button(event: &CalendarEvent, date: NaiveDate) -> gtk::Button {
    let text = if event.all_day || event.start.date_naive() != date {
        event.summary.clone()
    } else {
        format!("{} {}", event.start.format("%H:%M"), event.summary)
    };
    let button = gtk::Button::new();
    button.style_context().add_class("calendar-chip");
    button.style_context().add_class(&color_class(event.color));
    let label = gtk::Label::new(Some(&text));
    label.set_xalign(0.0);
    label.set_ellipsize(gtk::pango::EllipsizeMode::End);
    label.set_max_width_chars(32);
    button.add(&label);

    let popover = gtk::Popover::new(Some(&button));
    popover.style_context().add_class("calendar-event-popover");
    let details = gtk::Box::new(gtk::Orientation::Vertical, 5);
    details.style_context().add_class("calendar-event-details");
    let title = gtk::Label::new(Some(&event.summary));
    title.set_xalign(0.0);
    title.set_line_wrap(true);
    title.style_context().add_class("calendar-detail-title");
    let source = gtk::Label::new(Some(&format!("●  {}", event.calendar)));
    source.set_xalign(0.0);
    source.style_context().add_class("calendar-detail-source");
    source.style_context().add_class(&color_class(event.color));
    let when = gtk::Label::new(Some(&format_event_details(event)));
    when.set_xalign(0.0);
    when.style_context().add_class("calendar-detail-meta");
    details.pack_start(&title, false, false, 0);
    details.pack_start(&source, false, false, 0);
    details.pack_start(&when, false, false, 0);
    if !event.location.is_empty() {
        let location = gtk::Label::new(Some(&format!("󰍎  {}", event.location)));
        location.set_xalign(0.0);
        location.set_line_wrap(true);
        location.style_context().add_class("calendar-detail-meta");
        details.pack_start(&location, false, false, 0);
    }
    if !event.url.is_empty() {
        let open = gtk::Button::with_label("Open event  󰏌");
        open.style_context().add_class("calendar-detail-open");
        let target = event.url.clone();
        open.connect_clicked(move |_| crate::telemetry::spawn("xdg-open", &[&target]));
        details.pack_start(&open, false, false, 0);
    }
    popover.add(&details);
    let click_popover = popover.clone();
    button.connect_clicked(move |_| {
        click_popover.show_all();
        click_popover.popup();
    });
    button
}

fn calendar_more_button(
    date: NaiveDate,
    events: &[&CalendarEvent],
    visible_events: usize,
) -> gtk::Button {
    let button =
        gtk::Button::with_label(&format!("+{}", events.len().saturating_sub(visible_events)));
    button.style_context().add_class("calendar-more");
    button.set_tooltip_text(Some("Show every event on this day"));

    let popover = gtk::Popover::new(Some(&button));
    popover.style_context().add_class("calendar-event-popover");
    let details = gtk::Box::new(gtk::Orientation::Vertical, 6);
    details.style_context().add_class("calendar-event-details");
    let heading = gtk::Label::new(Some(&date.format("%A, %B %-d").to_string()));
    heading.set_xalign(0.0);
    heading.style_context().add_class("calendar-detail-title");
    details.pack_start(&heading, false, false, 0);

    let scroll = gtk::ScrolledWindow::new(None::<&gtk::Adjustment>, None::<&gtk::Adjustment>);
    scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scroll.set_max_content_height(280);
    scroll.set_propagate_natural_height(true);
    let list = gtk::Box::new(gtk::Orientation::Vertical, 4);
    for event in events {
        let row = gtk::Button::new();
        row.style_context().add_class("calendar-day-detail");
        row.style_context().add_class(&color_class(event.color));
        let content = gtk::Box::new(gtk::Orientation::Vertical, 1);
        let title = gtk::Label::new(Some(&event.summary));
        title.set_xalign(0.0);
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        title.set_max_width_chars(32);
        let meta = if event.all_day {
            format!("All day · {}", event.calendar)
        } else {
            format!("{} · {}", event.start.format("%H:%M"), event.calendar)
        };
        let meta = gtk::Label::new(Some(&meta));
        meta.set_xalign(0.0);
        meta.style_context().add_class("calendar-detail-meta");
        content.pack_start(&title, false, false, 0);
        content.pack_start(&meta, false, false, 0);
        row.add(&content);
        if event.url.is_empty() {
            row.set_sensitive(false);
        } else {
            let target = event.url.clone();
            row.connect_clicked(move |_| crate::telemetry::spawn("xdg-open", &[&target]));
        }
        list.pack_start(&row, false, false, 0);
    }
    scroll.add(&list);
    details.pack_start(&scroll, false, false, 0);
    popover.add(&details);
    let click_popover = popover.clone();
    button.connect_clicked(move |_| {
        click_popover.show_all();
        click_popover.popup();
    });
    button
}

fn render_period(grid: &gtk::Grid, period_start: NaiveDate, events: &[CalendarEvent]) {
    clear_container(grid.upcast_ref());
    for (column, name) in ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        .iter()
        .enumerate()
    {
        let label = gtk::Label::new(Some(name));
        label.style_context().add_class("calendar-weekday");
        grid.attach(&label, column as i32, 0, 1, 1);
    }

    let today = Local::now().date_naive();
    let (first, _) = period_bounds(period_start);
    for offset in 0..(CALENDAR_WEEKS * 7) {
        let date = first + ChronoDuration::days(offset);
        let cell = gtk::Box::new(gtk::Orientation::Vertical, 2);
        cell.style_context().add_class("calendar-day");
        if date == today {
            cell.style_context().add_class("today");
        }
        cell.set_size_request(116, 56);
        let day_events: Vec<_> = events
            .iter()
            .filter(|event| event_occurs_on(event, date))
            .collect();
        let day_header = gtk::Box::new(gtk::Orientation::Horizontal, 3);
        let day = gtk::Label::new(Some(&date.day().to_string()));
        day.set_xalign(0.0);
        day.style_context().add_class("calendar-day-number");
        day_header.pack_start(&day, true, true, 0);
        if day_events.len() > VISIBLE_EVENTS_PER_DAY {
            let more = calendar_more_button(date, &day_events, VISIBLE_EVENTS_PER_DAY);
            day_header.pack_end(&more, false, false, 0);
        }
        cell.pack_start(&day_header, false, false, 0);
        for event in day_events.iter().take(VISIBLE_EVENTS_PER_DAY) {
            cell.pack_start(&calendar_event_button(event, date), false, false, 0);
        }
        grid.attach(&cell, (offset % 7) as i32, (offset / 7 + 1) as i32, 1, 1);
    }
    grid.show_all();
}

fn render_feeds(
    container: &gtk::Box,
    sender: &glib::Sender<CalendarUpdate>,
    viewed_period: &Rc<RefCell<NaiveDate>>,
) {
    clear_container(container.upcast_ref());
    for feed in load_calendar_feeds() {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 7);
        row.style_context().add_class("calendar-feed");
        let color = feed.color.unwrap_or(0) % CALENDAR_COLOR_COUNT;
        let swatch = gtk::Button::with_label("●");
        swatch.style_context().add_class("calendar-feed-color");
        swatch.style_context().add_class(&color_class(color));
        swatch.set_tooltip_text(Some("Change calendar color"));
        let name = gtk::Label::new(Some(&feed.name));
        name.set_xalign(0.0);
        name.set_hexpand(true);
        let remove = gtk::Button::with_label("󰆴");
        remove.style_context().add_class("calendar-feed-remove");
        remove.set_tooltip_text(Some("Remove this calendar"));
        row.pack_start(&swatch, false, false, 0);
        row.pack_start(&name, true, true, 0);
        row.pack_end(&remove, false, false, 0);
        container.pack_start(&row, false, false, 0);

        let id = feed.id;
        let color_box = container.clone();
        let color_sender = sender.clone();
        let color_period = viewed_period.clone();
        swatch.connect_clicked(move |_| {
            let mut feeds = load_calendar_feeds();
            if let Some(feed) = feeds.iter_mut().find(|feed| feed.id == id) {
                feed.color = Some((feed.color.unwrap_or(0) + 1) % CALENDAR_COLOR_COUNT);
            }
            if let Err(error) = save_calendar_feeds(&feeds) {
                let _ = color_sender.send(CalendarUpdate::Error(error.to_string()));
                return;
            }
            render_feeds(&color_box, &color_sender, &color_period);
            fetch_calendar(color_sender.clone(), *color_period.borrow());
        });

        let remove_box = container.clone();
        let remove_sender = sender.clone();
        let remove_period = viewed_period.clone();
        remove.connect_clicked(move |_| {
            let mut feeds = load_calendar_feeds();
            feeds.retain(|feed| feed.id != id);
            if let Err(error) = save_calendar_feeds(&feeds) {
                let _ = remove_sender.send(CalendarUpdate::Error(error.to_string()));
                return;
            }
            render_feeds(&remove_box, &remove_sender, &remove_period);
            fetch_calendar(remove_sender.clone(), *remove_period.borrow());
        });
    }
    container.show_all();
}

fn desktop_window(
    name: &str,
    monitor_index: i32,
    side: Option<Edge>,
    vertical: Edge,
    width: i32,
) -> gtk::Window {
    let window = gtk::Window::new(gtk::WindowType::Toplevel);
    window.set_widget_name(name);
    window.style_context().add_class("nixie-desktop");
    window.set_app_paintable(true);
    window.set_decorated(false);
    window.set_resizable(false);
    window.set_default_size(width, -1);
    if let Some(screen) = gtk::prelude::WidgetExt::screen(&window) {
        if let Some(visual) = screen.rgba_visual() {
            window.set_visual(Some(&visual));
        }
    }
    layer_shell::init_for_window(&window);
    layer_shell::set_namespace(&window, name);
    layer_shell::set_layer(&window, Layer::Bottom);
    layer_shell::set_anchor(&window, vertical, true);
    layer_shell::set_margin(
        &window,
        vertical,
        if vertical == Edge::Top { 66 } else { 28 },
    );
    if let Some(side) = side {
        layer_shell::set_anchor(&window, side, true);
        layer_shell::set_margin(&window, side, 24);
    } else {
        layer_shell::set_anchor(&window, Edge::Left, true);
        layer_shell::set_anchor(&window, Edge::Right, true);
        layer_shell::set_margin(&window, Edge::Left, 24);
        layer_shell::set_margin(&window, Edge::Right, 24);
    }
    layer_shell::set_exclusive_zone(&window, -1);
    layer_shell::set_keyboard_mode(&window, KeyboardMode::OnDemand);
    if let Some(display) = gdk::Display::default() {
        if let Some(monitor) = display.monitor(monitor_index.max(0)) {
            layer_shell::set_monitor(&window, &monitor);
        }
    }
    window
}

pub fn start(enabled: bool, monitor_index: i32, refresh_minutes: u64) -> Option<DesktopManager> {
    if !enabled {
        return None;
    }
    let todo_window = desktop_window(
        "nixie-desktop-todo",
        monitor_index,
        Some(Edge::Left),
        Edge::Top,
        350,
    );

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

    todo_window.add(&root);
    todo_window.show_all();

    let calendar_window = desktop_window(
        "nixie-desktop-calendar",
        monitor_index,
        None,
        Edge::Bottom,
        900,
    );
    let root = gtk::Box::new(gtk::Orientation::Vertical, 8);
    root.style_context().add_class("desktop-card");
    root.style_context().add_class("calendar-card");

    let viewed_period = Rc::new(RefCell::new(week_start(Local::now().date_naive())));
    let calendar_header = gtk::Box::new(gtk::Orientation::Horizontal, 7);
    let calendar_status = gtk::Label::new(Some("Syncing calendars…"));
    calendar_status.set_xalign(0.0);
    calendar_status.style_context().add_class("calendar-status");
    let previous = gtk::Button::with_label("󰁍");
    previous.set_tooltip_text(Some("Previous four weeks"));
    let today = gtk::Button::with_label("Today");
    today.set_tooltip_text(Some("Put the current week first"));
    let next = gtk::Button::with_label("󰁔");
    next.set_tooltip_text(Some("Next four weeks"));
    let manage = gtk::Button::with_label("󰒓");
    manage.set_tooltip_text(Some("Calendars and colors"));
    let refresh = gtk::Button::with_label("󰑐");
    refresh.set_tooltip_text(Some("Refresh these four weeks"));
    for button in [&previous, &today, &next, &manage, &refresh] {
        button.style_context().add_class("calendar-nav");
    }
    calendar_header.pack_start(&calendar_status, true, true, 0);
    calendar_header.pack_end(&refresh, false, false, 0);
    calendar_header.pack_end(&manage, false, false, 0);
    calendar_header.pack_end(&next, false, false, 0);
    calendar_header.pack_end(&today, false, false, 0);
    calendar_header.pack_end(&previous, false, false, 0);
    root.pack_start(&calendar_header, false, false, 0);

    let manager = gtk::Revealer::new();
    manager.set_transition_type(gtk::RevealerTransitionType::SlideDown);
    manager.set_transition_duration(180);
    let manager_box = gtk::Box::new(gtk::Orientation::Vertical, 7);
    manager_box.style_context().add_class("calendar-manager");
    let manager_header = gtk::Box::new(gtk::Orientation::Horizontal, 7);
    let manager_title = gtk::Label::new(Some("CALENDAR SOURCES"));
    manager_title.set_xalign(0.0);
    manager_title
        .style_context()
        .add_class("calendar-manager-title");
    let add_calendar = gtk::Button::with_label("＋ Add calendar");
    add_calendar.style_context().add_class("calendar-add");
    manager_header.pack_start(&manager_title, true, true, 0);
    manager_header.pack_end(&add_calendar, false, false, 0);
    manager_box.pack_start(&manager_header, false, false, 0);

    let feeds_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
    manager_box.pack_start(&feeds_box, false, false, 0);

    let setup = gtk::Box::new(gtk::Orientation::Vertical, 7);
    setup.style_context().add_class("calendar-setup");
    let setup_help = gtk::Label::new(Some(
        "Google Calendar → Settings → Integrate calendar → Secret address in iCal format",
    ));
    setup_help.set_xalign(0.0);
    setup_help.set_line_wrap(true);
    let name_entry = gtk::Entry::new();
    name_entry.set_placeholder_text(Some("Calendar name (e.g. Personal)"));
    let secret_entry = gtk::Entry::new();
    secret_entry.set_placeholder_text(Some("Paste an HTTPS iCal address"));
    secret_entry.set_visibility(false);
    let setup_actions = gtk::Box::new(gtk::Orientation::Horizontal, 7);
    let open_settings = gtk::Button::with_label("Open Google settings");
    let connect = gtk::Button::with_label("Add calendar");
    setup_actions.pack_start(&open_settings, true, true, 0);
    setup_actions.pack_end(&connect, false, false, 0);
    setup.pack_start(&setup_help, false, false, 0);
    setup.pack_start(&name_entry, false, false, 0);
    setup.pack_start(&secret_entry, false, false, 0);
    setup.pack_start(&setup_actions, false, false, 0);
    manager_box.pack_start(&setup, false, false, 0);
    manager.add(&manager_box);
    root.pack_start(&manager, false, false, 0);

    let calendar_grid = gtk::Grid::new();
    calendar_grid.style_context().add_class("calendar-grid");
    calendar_grid.set_column_homogeneous(true);
    calendar_grid.set_column_spacing(3);
    calendar_grid.set_row_spacing(3);
    root.pack_start(&calendar_grid, false, false, 0);
    render_period(&calendar_grid, *viewed_period.borrow(), &[]);

    calendar_window.add(&root);
    calendar_window.show_all();
    let connected = !load_calendar_feeds().is_empty();
    setup.set_visible(!connected);
    manager.set_reveal_child(!connected);
    refresh.set_sensitive(connected);

    let (calendar_tx, calendar_rx) = glib::MainContext::channel(glib::Priority::default());
    let status_ref = calendar_status.clone();
    let grid_ref = calendar_grid.clone();
    let setup_ref = setup.clone();
    let manager_ref = manager.clone();
    let feeds_ref = feeds_box.clone();
    let refresh_ref = refresh.clone();
    let feed_sender = calendar_tx.clone();
    let receiver_period = viewed_period.clone();
    calendar_rx.attach(None, move |update| {
        match update {
            CalendarUpdate::Loading(period_start) if period_start == *receiver_period.borrow() => {
                status_ref.set_label("Syncing calendars…")
            }
            CalendarUpdate::Loading(_) => {}
            CalendarUpdate::Events {
                period_start,
                events,
                feeds,
                failed,
            } if period_start == *receiver_period.borrow() => {
                if failed.is_empty() {
                    status_ref.set_label(&format!(
                        "{} calendars · synced {} · {} events",
                        feeds.len(),
                        Local::now().format("%H:%M"),
                        events.len()
                    ));
                } else {
                    status_ref.set_label(&format!(
                        "{} events · unavailable: {}",
                        events.len(),
                        failed.join(", ")
                    ));
                }
                refresh_ref.set_sensitive(true);
                render_feeds(&feeds_ref, &feed_sender, &receiver_period);
                render_period(&grid_ref, period_start, &events);
            }
            CalendarUpdate::Events { .. } => {}
            CalendarUpdate::Error(error) => {
                status_ref.set_label(&format!("Calendar error · {error}"));
            }
            CalendarUpdate::Disconnected(period_start)
                if period_start == *receiver_period.borrow() =>
            {
                status_ref.set_label("Calendar not connected");
                setup_ref.show();
                manager_ref.set_reveal_child(true);
                render_feeds(&feeds_ref, &feed_sender, &receiver_period);
                render_period(&grid_ref, period_start, &[]);
                refresh_ref.set_sensitive(false);
            }
            CalendarUpdate::Disconnected(_) => {}
        }
        glib::Continue(true)
    });

    let manage_panel = manager.clone();
    manage.connect_clicked(move |_| {
        manage_panel.set_reveal_child(!manage_panel.reveals_child());
    });
    let add_setup = setup.clone();
    let add_name = name_entry.clone();
    add_calendar.connect_clicked(move |_| {
        add_setup.show();
        add_name.grab_focus();
    });
    open_settings
        .connect_clicked(|_| crate::telemetry::spawn("xdg-open", &[GOOGLE_CALENDAR_SETTINGS]));

    let previous_tx = calendar_tx.clone();
    let previous_period = viewed_period.clone();
    let previous_grid = calendar_grid.clone();
    previous.connect_clicked(move |_| {
        let period_start = shift_period(*previous_period.borrow(), -1);
        *previous_period.borrow_mut() = period_start;
        render_period(&previous_grid, period_start, &[]);
        fetch_calendar(previous_tx.clone(), period_start);
    });
    let next_tx = calendar_tx.clone();
    let next_period = viewed_period.clone();
    let next_grid = calendar_grid.clone();
    next.connect_clicked(move |_| {
        let period_start = shift_period(*next_period.borrow(), 1);
        *next_period.borrow_mut() = period_start;
        render_period(&next_grid, period_start, &[]);
        fetch_calendar(next_tx.clone(), period_start);
    });
    let today_tx = calendar_tx.clone();
    let today_period = viewed_period.clone();
    let today_grid = calendar_grid.clone();
    today.connect_clicked(move |_| {
        let period_start = week_start(Local::now().date_naive());
        *today_period.borrow_mut() = period_start;
        render_period(&today_grid, period_start, &[]);
        fetch_calendar(today_tx.clone(), period_start);
    });

    let connect_tx = calendar_tx.clone();
    let connect_status = calendar_status.clone();
    let connect_name = name_entry.clone();
    let connect_entry = secret_entry.clone();
    let connect_setup = setup.clone();
    let connect_feeds = feeds_box.clone();
    let connect_period = viewed_period.clone();
    connect.connect_clicked(move |_| {
        let value = connect_entry.text().trim().to_string();
        if !valid_calendar_url(&value) {
            connect_status.set_label("Use a safe HTTPS iCal address");
            return;
        }
        let mut feeds = load_calendar_feeds();
        if feeds.iter().any(|feed| feed.url == value) {
            connect_status.set_label("That iCal feed is already connected");
            return;
        }
        let entered_name = connect_name.text().trim().to_string();
        let name = if entered_name.is_empty() {
            format!("Calendar {}", feeds.len() + 1)
        } else {
            entered_name
        };
        let color = (feeds.len() as u8) % CALENDAR_COLOR_COUNT;
        feeds.push(CalendarFeed {
            id: next_todo_id(),
            name,
            url: value,
            color: Some(color),
        });
        match save_calendar_feeds(&feeds) {
            Ok(()) => {
                connect_name.set_text("");
                connect_entry.set_text("");
                connect_setup.hide();
                render_feeds(&connect_feeds, &connect_tx, &connect_period);
                fetch_calendar(connect_tx.clone(), *connect_period.borrow());
            }
            Err(error) => {
                connect_status.set_label(&format!("Cannot save calendar secret · {error}"))
            }
        }
    });
    let refresh_tx = calendar_tx.clone();
    let refresh_period = viewed_period.clone();
    refresh.connect_clicked(move |_| fetch_calendar(refresh_tx.clone(), *refresh_period.borrow()));
    render_feeds(&feeds_box, &calendar_tx, &viewed_period);

    fetch_calendar(calendar_tx.clone(), *viewed_period.borrow());
    let timer_tx = calendar_tx.clone();
    let timer_period = viewed_period.clone();
    let refresh_seconds = refresh_minutes
        .max(1)
        .saturating_mul(60)
        .min(u32::MAX as u64) as u32;
    glib::timeout_add_seconds_local(refresh_seconds, move || {
        fetch_calendar(timer_tx.clone(), *timer_period.borrow());
        glib::Continue(true)
    });

    Some(DesktopManager {
        _todo_window: todo_window,
        _calendar_window: calendar_window,
    })
}

#[cfg(test)]
mod tests {
    use super::{
        atomic_private_write, normalize_feed_colors, parse_calendar, period_bounds, shift_period,
        valid_calendar_url, week_start, CalendarFeed,
    };
    use chrono::{Datelike, Local, NaiveDate, TimeZone};
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn accepts_safe_https_ical_feeds() {
        assert!(valid_calendar_url(
            "https://calendar.google.com/calendar/ical/user/private-token/basic.ics"
        ));
        assert!(!valid_calendar_url("http://calendar.google.com/basic.ics"));
        assert!(valid_calendar_url("https://example.com/basic.ics"));
        assert!(valid_calendar_url(
            "https://example.com/calendar?format=ical&token=secret"
        ));
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
    fn period_is_four_weeks_starting_on_monday() {
        let today = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        let start = week_start(today);
        let (first, last) = period_bounds(start);
        assert_eq!(first, NaiveDate::from_ymd_opt(2026, 8, 17).unwrap());
        assert_eq!(last, NaiveDate::from_ymd_opt(2026, 9, 13).unwrap());
        assert_eq!(
            shift_period(start, -1),
            NaiveDate::from_ymd_opt(2026, 7, 20).unwrap()
        );
        assert_eq!(
            shift_period(start, 1),
            NaiveDate::from_ymd_opt(2026, 9, 14).unwrap()
        );
    }

    #[test]
    fn missing_calendar_colors_are_stably_assigned() {
        let mut feeds = vec![
            CalendarFeed {
                id: 1,
                name: "One".into(),
                url: "https://example.com/one.ics".into(),
                color: None,
            },
            CalendarFeed {
                id: 2,
                name: "Two".into(),
                url: "https://example.com/two.ics".into(),
                color: None,
            },
        ];
        assert!(normalize_feed_colors(&mut feeds));
        assert_eq!(feeds[0].color, Some(0));
        assert_eq!(feeds[1].color, Some(1));
        assert!(!normalize_feed_colors(&mut feeds));
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
