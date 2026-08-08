use chrono::{Local, Timelike};
use gtk::cairo::{Context, Format, ImageSurface, Operator, Region};
use gtk::gdk;
use gtk::prelude::*;
use gtk_layer_shell::{self as layer_shell, Edge, Layer};
use std::cell::{Cell, RefCell};
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

const GHOSTS: [[char; 3]; 8] = [
    ['4', '7', '0'],
    ['3', '9', '1'],
    ['3', '1', '8'],
    ['2', '4', '0'],
    ['2', '6', '8'],
    ['0', '2', '1'],
    ['3', '1', '0'],
    ['2', '8', '7'],
];
const STABLE_DIGITS: [Option<char>; 8] = [
    Some('1'),
    None,
    Some('0'),
    Some('4'),
    Some('8'),
    Some('5'),
    Some('9'),
    Some('6'),
];
const STABLE_DOTS: [bool; 8] = [false, true, false, false, false, false, false, false];
const GLYPH_PAD: f64 = 38.0;
const CELL_WIDTH_FACTOR: f64 = 0.68;
const METER_Y_OFFSET_AT_300: f64 = -53.0;
const DOT_MARGIN_LEFT_AT_300: f64 = 70.0;
const DOT_MARGIN_TOP_AT_300: f64 = -5.0;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Stable,
    Rolling,
    Clock,
}

fn phase_for_second(second: u32) -> Phase {
    match second {
        53 | 54 | 5 | 6 => Phase::Rolling,
        55..=59 | 0..=4 => Phase::Clock,
        _ => Phase::Stable,
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct MeterState {
    digits: [Option<char>; 8],
    dots: [bool; 8],
    rolling: bool,
    glow: u8,
}

impl Default for MeterState {
    fn default() -> Self {
        Self {
            digits: STABLE_DIGITS,
            dots: STABLE_DOTS,
            rolling: false,
            glow: 0,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
struct GlyphKey {
    value: char,
    size: i32,
    kind: u8,
}

struct Glyph {
    surface: ImageSurface,
    pad: f64,
}

#[derive(Default)]
struct GlyphCache {
    values: HashMap<GlyphKey, Glyph>,
    backplates: HashMap<i32, ImageSurface>,
}

impl GlyphCache {
    fn glyph(&mut self, key: GlyphKey) -> Option<&Glyph> {
        match self.values.entry(key) {
            Entry::Occupied(value) => Some(value.into_mut()),
            Entry::Vacant(value) => Some(value.insert(render_glyph(key)?)),
        }
    }

    fn backplate(&mut self, size: i32) -> Option<ImageSurface> {
        if let Some(surface) = self.backplates.get(&size) {
            return Some(surface.clone());
        }
        let font_size = size as f64;
        let cell_width = font_size * CELL_WIDTH_FACTOR;
        let cell_height = font_size * 1.35;
        let surface = ImageSurface::create(
            Format::ARgb32,
            (cell_width * 8.0 + GLYPH_PAD * 2.0).ceil() as i32,
            (cell_height + GLYPH_PAD * 2.0).ceil() as i32,
        )
        .ok()?;
        let cr = Context::new(&surface).ok()?;
        cr.set_operator(Operator::Source);
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.0);
        cr.paint().ok()?;
        cr.set_operator(Operator::Over);
        for (tube, ghosts) in GHOSTS.iter().enumerate() {
            let x = GLYPH_PAD + tube as f64 * cell_width;
            for &ghost in ghosts {
                paint_glyph(&cr, self, ghost, size, 0, x, GLYPH_PAD);
            }
            let dot_x = x + DOT_MARGIN_LEFT_AT_300 * 0.5 * (font_size / 300.0);
            paint_glyph(&cr, self, '.', size, 1, dot_x, GLYPH_PAD);
        }
        surface.flush();
        self.backplates.insert(size, surface.clone());
        Some(surface)
    }
}

fn render_glyph(key: GlyphKey) -> Option<Glyph> {
    let size = key.size as f64;
    let cell_width = size * CELL_WIDTH_FACTOR;
    let cell_height = size * 1.35;
    let pad = GLYPH_PAD;
    let surface = ImageSurface::create(
        Format::ARgb32,
        (cell_width + pad * 2.0).ceil() as i32,
        (cell_height + pad * 2.0).ceil() as i32,
    )
    .ok()?;
    let cr = Context::new(&surface).ok()?;
    cr.set_operator(Operator::Source);
    cr.set_source_rgba(0.0, 0.0, 0.0, 0.0);
    cr.paint().ok()?;
    cr.set_operator(Operator::Over);

    let is_dot = key.kind == 1 || key.kind == 3 || key.kind >= 10;
    cr.select_font_face(
        if is_dot { "TT Chocolates Trl" } else { "BO NX" },
        gtk::cairo::FontSlant::Normal,
        gtk::cairo::FontWeight::Normal,
    );
    cr.set_font_size(size);
    let text = key.value.to_string();
    let extents = cr.text_extents(&text).ok()?;
    let font_extents = cr.font_extents().ok()?;
    let x = pad + (cell_width - extents.width()) / 2.0 - extents.x_bearing();
    // Eww's overlay labels shared a Pango line box. Centre Cairo's equivalent
    // font line, rather than each visible glyph's ink bounds, so the period
    // naturally rests at the font baseline like the original wallpaper.
    let y = pad
        + (cell_height - font_extents.ascent() - font_extents.descent()) / 2.0
        + font_extents.ascent()
        + if is_dot {
            DOT_MARGIN_TOP_AT_300 * size / 300.0
        } else {
            0.0
        };

    match key.kind {
        0 | 1 => draw_text(&cr, &text, x, y, (0.208, 0.090, 0.039, 1.0)),
        _ => {
            let glow = match key.kind {
                4 | 12 => 8.0,
                5 | 13 => 15.0,
                6 | 14 => 5.0,
                7 | 15 => 19.0,
                _ => 11.0,
            };
            draw_glow(&cr, &text, x, y, glow);
            draw_text(&cr, &text, x, y, (0.902, 0.580, 0.361, 1.0));
        }
    }
    surface.flush();
    Some(Glyph { surface, pad })
}

fn draw_text(cr: &Context, text: &str, x: f64, y: f64, color: (f64, f64, f64, f64)) {
    cr.set_source_rgba(color.0, color.1, color.2, color.3);
    cr.move_to(x, y);
    let _ = cr.show_text(text);
}

fn draw_glow(cr: &Context, text: &str, x: f64, y: f64, radius: f64) {
    for ring in [radius, radius * 0.55, radius * 0.25] {
        let alpha = if ring > 12.0 { 0.055 } else { 0.09 };
        for step in 0..12 {
            let angle = step as f64 * std::f64::consts::TAU / 12.0;
            draw_text(
                cr,
                text,
                x + angle.cos() * ring,
                y + angle.sin() * ring,
                (0.792, 0.376, 0.043, alpha),
            );
        }
    }
}

struct MeterSurface {
    monitor: gdk::Monitor,
    window: gtk::Window,
    area: gtk::DrawingArea,
}

pub struct DivergenceManager {
    _surfaces: Rc<RefCell<Vec<MeterSurface>>>,
}

pub fn start(enabled: bool, monitors: &str, roll_fps: u32) -> Option<DivergenceManager> {
    if !enabled {
        return None;
    }
    let display = gdk::Display::default()?;
    let state = Rc::new(RefCell::new(MeterState::default()));
    let surfaces = Rc::new(RefCell::new(Vec::new()));
    let all_monitors = monitors.eq_ignore_ascii_case("all");

    if all_monitors {
        for index in 0..display.n_monitors() {
            if let Some(monitor) = display.monitor(index) {
                add_surface(&surfaces, &state, &monitor);
            }
        }
    } else if let Some(monitor) = display.primary_monitor().or_else(|| display.monitor(0)) {
        add_surface(&surfaces, &state, &monitor);
    }

    if all_monitors {
        let added_surfaces = surfaces.clone();
        let added_state = state.clone();
        display.connect_monitor_added(move |_, monitor| {
            add_surface(&added_surfaces, &added_state, monitor);
        });
        let removed_surfaces = surfaces.clone();
        display.connect_monitor_removed(move |_, monitor| {
            let mut values = removed_surfaces.borrow_mut();
            if let Some(index) = values.iter().position(|value| value.monitor == *monitor) {
                values.remove(index).window.hide();
            }
        });
    }

    let random = Rc::new(Cell::new(
        Local::now().timestamp_nanos_opt().unwrap_or_default() as u64 ^ 0x9e3779b97f4a7c15,
    ));
    update_and_schedule(state, surfaces.clone(), random, roll_fps.clamp(1, 60));
    Some(DivergenceManager {
        _surfaces: surfaces,
    })
}

fn add_surface(
    surfaces: &Rc<RefCell<Vec<MeterSurface>>>,
    state: &Rc<RefCell<MeterState>>,
    monitor: &gdk::Monitor,
) {
    if surfaces
        .borrow()
        .iter()
        .any(|value| value.monitor == *monitor)
    {
        return;
    }

    let window = gtk::Window::new(gtk::WindowType::Toplevel);
    window.style_context().add_class("nixie-divergence");
    window.set_app_paintable(true);
    window.set_decorated(false);
    layer_shell::init_for_window(&window);
    layer_shell::set_namespace(&window, "nixie-divergence");
    layer_shell::set_layer(&window, Layer::Bottom);
    layer_shell::set_monitor(&window, monitor);
    layer_shell::set_exclusive_zone(&window, -1);
    layer_shell::set_keyboard_interactivity(&window, false);

    let geometry = monitor.geometry();
    let max_by_width = geometry.width() as f64 * 0.90 / (8.0 * CELL_WIDTH_FACTOR);
    let max_by_height = geometry.height() as f64 * 0.62;
    let font_size = 300.0_f64.min(max_by_width).min(max_by_height).max(72.0);
    let meter_width = (font_size * CELL_WIDTH_FACTOR * 8.0 + GLYPH_PAD * 2.0).ceil() as i32;
    let offset = METER_Y_OFFSET_AT_300.abs() * (font_size / 300.0);
    let meter_height = (font_size * 1.35 + GLYPH_PAD * 2.0 + offset * 2.0).ceil() as i32;
    window.set_default_size(meter_width, meter_height);
    layer_shell::set_anchor(&window, Edge::Top, true);
    layer_shell::set_anchor(&window, Edge::Left, true);
    layer_shell::set_margin(&window, Edge::Top, (geometry.height() - meter_height) / 2);
    layer_shell::set_margin(&window, Edge::Left, (geometry.width() - meter_width) / 2);

    if let Some(screen) = WidgetExt::screen(&window) {
        if let Some(visual) = screen.rgba_visual() {
            window.set_visual(Some(&visual));
        }
    }
    window.connect_realize(|value| {
        if let Some(surface) = value.window() {
            let empty = Region::create();
            surface.input_shape_combine_region(&empty, 0, 0);
        }
    });

    let area = gtk::DrawingArea::new();
    area.set_size_request(meter_width, meter_height);
    area.set_hexpand(true);
    area.set_vexpand(true);
    let draw_state = state.clone();
    let cache = Rc::new(RefCell::new(GlyphCache::default()));
    let draw_logged = Rc::new(Cell::new(false));
    area.connect_draw(move |area, cr| {
        draw_meter(
            cr,
            area.allocated_width(),
            area.allocated_height(),
            font_size,
            &draw_state.borrow(),
            &mut cache.borrow_mut(),
        );
        if !draw_logged.replace(true) {
            log::info!(
                "divergence surface rendered at {}x{} with {:.0}px glyphs",
                area.allocated_width(),
                area.allocated_height(),
                font_size
            );
        }
        gtk::Inhibit(false)
    });
    window.add(&area);
    window.show_all();
    let initial_area = area.clone();
    glib::idle_add_local_once(move || initial_area.queue_draw());
    surfaces.borrow_mut().push(MeterSurface {
        monitor: monitor.clone(),
        window,
        area,
    });
}

fn draw_meter(
    cr: &Context,
    width: i32,
    height: i32,
    font_size: f64,
    state: &MeterState,
    cache: &mut GlyphCache,
) {
    cr.set_operator(Operator::Source);
    cr.set_source_rgba(0.0, 0.0, 0.0, 0.0);
    let _ = cr.paint();
    cr.set_operator(Operator::Over);

    let size = font_size.round() as i32;
    let cell_width = font_size * CELL_WIDTH_FACTOR;
    let cell_height = font_size * 1.35;
    let start_x = (width as f64 - cell_width * 8.0) / 2.0;
    let y = (height as f64 - cell_height) / 2.0 + METER_Y_OFFSET_AT_300 * (font_size / 300.0);

    if let Some(backplate) = cache.backplate(size) {
        let _ = cr.set_source_surface(&backplate, start_x - GLYPH_PAD, y - GLYPH_PAD);
        let _ = cr.paint();
    }

    for tube in 0..8 {
        let x = start_x + tube as f64 * cell_width;
        if let Some(digit) = state.digits[tube] {
            let kind = if state.rolling { 4 + state.glow } else { 2 };
            paint_glyph(cr, cache, digit, size, kind, x, y);
        }
        if state.dots[tube] {
            let kind = if state.rolling { 12 + state.glow } else { 3 };
            // GtkOverlay centres the child's total box. A one-sided 70px CSS
            // margin therefore moved the dot's ink by half that amount.
            let dot_x = x + DOT_MARGIN_LEFT_AT_300 * 0.5 * (font_size / 300.0);
            paint_glyph(cr, cache, '.', size, kind, dot_x, y);
        }
    }
}

fn paint_glyph(
    cr: &Context,
    cache: &mut GlyphCache,
    value: char,
    size: i32,
    kind: u8,
    x: f64,
    y: f64,
) {
    let Some(glyph) = cache.glyph(GlyphKey { value, size, kind }) else {
        return;
    };
    let _ = cr.set_source_surface(&glyph.surface, x - glyph.pad, y - glyph.pad);
    let _ = cr.paint();
}

fn update_and_schedule(
    state: Rc<RefCell<MeterState>>,
    surfaces: Rc<RefCell<Vec<MeterSurface>>>,
    random: Rc<Cell<u64>>,
    roll_fps: u32,
) {
    let now = Local::now();
    let phase = phase_for_second(now.second());
    let next = state_for_time(&now, phase, &random);
    let changed = phase == Phase::Rolling || *state.borrow() != next;
    if changed {
        *state.borrow_mut() = next;
        for surface in surfaces.borrow().iter() {
            surface.area.queue_draw();
        }
    }

    let delay = match phase {
        Phase::Rolling => Duration::from_millis(1000 / roll_fps.max(1) as u64),
        Phase::Clock => until_next_second(&now),
        Phase::Stable => until_second(&now, 53),
    };
    glib::timeout_add_local_once(delay.max(Duration::from_millis(10)), move || {
        update_and_schedule(state, surfaces, random, roll_fps)
    });
}

fn state_for_time(now: &chrono::DateTime<Local>, phase: Phase, random: &Cell<u64>) -> MeterState {
    match phase {
        Phase::Stable => MeterState::default(),
        Phase::Clock => {
            let time = format!("{:02}{:02}{:02}", now.hour(), now.minute(), now.second());
            let values: Vec<char> = time.chars().collect();
            MeterState {
                digits: [
                    Some(values[0]),
                    Some(values[1]),
                    None,
                    Some(values[2]),
                    Some(values[3]),
                    None,
                    Some(values[4]),
                    Some(values[5]),
                ],
                dots: [false, false, true, false, false, true, false, false],
                rolling: false,
                glow: 0,
            }
        }
        Phase::Rolling => {
            let mut digits = [None; 8];
            for value in &mut digits {
                *value = Some(char::from(b'0' + (next_random(random) % 10) as u8));
            }
            MeterState {
                digits,
                dots: [false; 8],
                rolling: true,
                glow: (next_random(random) % 4) as u8,
            }
        }
    }
}

fn next_random(state: &Cell<u64>) -> u64 {
    let mut value = state.get();
    value ^= value << 13;
    value ^= value >> 7;
    value ^= value << 17;
    state.set(value);
    value
}

fn until_next_second(now: &chrono::DateTime<Local>) -> Duration {
    Duration::from_nanos(1_000_000_000u64.saturating_sub(now.nanosecond() as u64))
}

fn until_second(now: &chrono::DateTime<Local>, second: u32) -> Duration {
    let seconds = if now.second() < second {
        second - now.second()
    } else {
        60 - now.second() + second
    };
    Duration::from_secs(seconds as u64)
        .saturating_sub(Duration::from_nanos(now.nanosecond() as u64))
}

#[cfg(test)]
mod tests {
    use super::{draw_meter, phase_for_second, GlyphCache, MeterState, Phase};
    use gtk::cairo::{Context, Format, ImageSurface};

    #[test]
    fn phase_boundaries_match_the_original_meter() {
        assert_eq!(phase_for_second(52), Phase::Stable);
        assert_eq!(phase_for_second(53), Phase::Rolling);
        assert_eq!(phase_for_second(54), Phase::Rolling);
        assert_eq!(phase_for_second(55), Phase::Clock);
        assert_eq!(phase_for_second(59), Phase::Clock);
        assert_eq!(phase_for_second(0), Phase::Clock);
        assert_eq!(phase_for_second(4), Phase::Clock);
        assert_eq!(phase_for_second(5), Phase::Rolling);
        assert_eq!(phase_for_second(6), Phase::Rolling);
        assert_eq!(phase_for_second(7), Phase::Stable);
    }

    #[test]
    fn stable_meter_renders_visible_pixels() {
        let mut surface = ImageSurface::create(Format::ARgb32, 1709, 587).unwrap();
        {
            let context = Context::new(&surface).unwrap();
            draw_meter(
                &context,
                1709,
                587,
                300.0,
                &MeterState::default(),
                &mut GlyphCache::default(),
            );
        }
        surface.flush();
        assert!(surface
            .data()
            .unwrap()
            .chunks_exact(4)
            .any(|pixel| pixel[3] != 0));
    }
}
