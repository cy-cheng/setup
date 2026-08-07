# Nixie desktop setup

This repository tracks the native Nixie desktop shell and the matching
Hyprland, Rofi, Dunst, and Fcitx configuration.

## What is included

- A GTK3/Rust layer-shell status bar with native tooltips and StatusNotifier tray.
- Event-driven workspace, audio, power, battery, network, Bluetooth, and
  notification updates; only hardware metrics and quota data use timers.
- Network, Bluetooth, audio, battery/power-profile, idle inhibitor, workspace,
  notification-center, and local Codex-quota modules.
- Event-driven Fcitx status plus a custom candidate UI. Candidates stay in a
  seven-item horizontal row beside the text cursor; Down expands a 5-column by
  5-row grid, arrows navigate (and continue across pages), `a` through `y`
  select, Enter commits, and Esc collapses. `Ctrl+Enter` commits Rime's shown
  注音 preedit literally. The panel flips above the cursor when needed.
- Workspace-aware notification history: selecting a captured notification
  returns to the Hyprland workspace where it arrived before restoring it. The
  right-anchored center shows a taller, scrollable history with four-line
  previews.
- A consistent near-black/amber Nixie theme for the bar, Rofi, Dunst, and Fcitx.

## Runtime dependencies

Hyprland 0.55+, Rust/Cargo, a C/C++ compiler, `pkgconf`, GTK3,
`gtk-layer-shell`, libpulse, NetworkManager/libnm, WirePlumber (`wpctl`), Fcitx 5 core
development headers, Dunst, Rofi 2, Blueberry, `powerprofilesctl`, and `jq`.

## Install

Run `./install.sh`, then log out and back in. The installer copies only the
tracked configuration, builds the optimized bar, and installs the two local
Fcitx addons. Hyprland starts `~/.config/nixie-shell/start-ui.sh`; Waybar and
Eww are not part of this setup.
