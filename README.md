# Nixie desktop setup

This repository tracks the native Nixie desktop shell and the matching
Hyprland, Rofi, Dunst, and Fcitx configuration.

## What is included

- A GTK3/Rust layer-shell status bar with native tooltips and StatusNotifier tray.
- A native, event-driven divergence-meter background on every monitor. It sleeps
  while showing `1.048596`, reveals the clock and rolls briefly at each minute,
  without Eww, Hyprpaper, or a polling script.
- Separate bottom-layer desktop cards: persistent Todos at top-left and a
  full-width rolling four-week calendar along the bottom, clear of the Nixie
  clock. The current week is the first row by default; arrow buttons move four
  weeks at a time. Events are color-coded by source and reveal their calendar
  and details only when clicked. Any number of read-only HTTPS
  iCal feeds can be named and connected. Their private addresses are stored only in
  `~/.config/nixie-shell/google-calendars.json` with mode `0600`; they are never
  part of this repository or exposed in `curl` process arguments.
- Event-driven workspace, audio, power, battery, network, Bluetooth, and
  notification updates; only hardware metrics and quota data use timers.
- Network, Bluetooth, audio, battery/power-profile, idle inhibitor, workspace,
  notification-center, and local Codex-quota modules.
- One-shot automatic timezone detection in the system panel. It uses GeoClue
  only when requested, maps the detected coordinates locally, and applies the
  IANA timezone through systemd's authenticated timezone service.
- Recovery for the UX3402ZA's intermittent I2C-HID touchpad hang. Runtime
  suspend is disabled only for the touchpad controller, and the touchpad is
  automatically rebound after system resume. `Super+Shift+T` performs the same
  targeted recovery on demand without rebooting.
- A context-aware hardware power button. It only wakes a sleeping display (or
  a suspended, locked session), but opens a Nixie action menu while the desktop
  is awake. Log out, reboot, and power off require a second confirmation that
  expires after five seconds; suspend locks the session first.
- Event-driven Fcitx status plus a custom candidate UI. Candidates stay in a
  seven-item horizontal row beside the text cursor; Down expands a 5-column by
  5-row grid, arrows navigate (and continue across pages), `A` through `Y`
  select, Enter commits, and Esc collapses. `Ctrl+Enter` commits Rime's shown
  注音 preedit literally. Candidate cells use uppercase monospaced labels and
  size themselves to the current text. Native Wayland clients use a compositor
  input-popup surface, which tracks the real caret and flips above it when
  needed; the GTK layer-shell renderer remains as a legacy fallback.
- Workspace-aware notification history: selecting a captured notification
  returns to the Hyprland workspace where it arrived before restoring it. The
  right-anchored center shows a taller, scrollable history with four-line
  previews.
- A consistent near-black/amber Nixie theme for the bar, Rofi, Dunst, and Fcitx.

## Runtime dependencies

Hyprland 0.55+, Rust/Cargo, a C/C++ compiler, `pkgconf`, GTK3,
`gtk-layer-shell`, libpulse, NetworkManager/libnm, WirePlumber (`wpctl`), Fcitx 5 core
development headers, Cairo/Pango, Wayland client development headers, Dunst,
Rofi 2, Blueberry, `powerprofilesctl`, and `jq`.
Automatic timezone detection additionally uses GeoClue, systemd's
`timedatectl`, and Hyprpolkitagent.
Touchpad recovery and power-button handling additionally use Polkit and `flock`
from util-linux. Their fixed, root-owned support files are installed with an
authentication prompt; the user-facing commands themselves remain unprivileged.
The optional Google Calendar feed also uses `curl` for HTTPS retrieval.

The divergence meter uses the locally installed `BO NX Medium` and
`TT Chocolates Trl ExtraLight` fonts. They are not redistributed by this
repository; the shell warns and uses Fontconfig fallbacks when either is absent.

## Install

Run `./install.sh`, then log out and back in. The installer copies only the
tracked configuration, builds the optimized bar, and installs the two local
Fcitx addons. Hyprland starts `~/.config/nixie-shell/start-ui.sh`; Waybar, Eww,
and Hyprpaper are not part of the running setup.

To connect Google Calendar, open an empty workspace and use the desktop card's
**Open Google settings** button. Under the chosen calendar, open **Integrate
calendar**, copy the **Secret address in iCal format**, give it a local display
name, paste it into the masked field, and click **Add calendar**. Open the source
manager (`󰒓`) to add more feeds, remove one, or click its color dot to cycle its
color. Feeds are read-only and refresh every 15 minutes; the refresh button
updates the visible four-week period immediately.
