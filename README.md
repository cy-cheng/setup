# Nixie desktop setup

This repository tracks the native Nixie desktop shell and the matching
Hyprland, Rofi, Dunst, and Fcitx configuration.

## What is included

- A GTK3/Rust layer-shell status bar with native tooltips and StatusNotifier tray.
- Network, Bluetooth, audio, battery/power-profile, idle inhibitor, workspace,
  notification-center, and local Codex-quota modules.
- Event-driven Fcitx status plus a custom candidate UI. Candidates stay in a
  compact horizontal row; Down expands a 4-column by 5-row grid, arrows
  navigate, Page Up/Down page, Enter commits, and Esc collapses.
- Workspace-aware notification history: selecting a captured notification
  returns to the Hyprland workspace where it arrived before restoring it.
- A consistent near-black/amber Nixie theme for the bar, Rofi, Dunst, and Fcitx.

## Runtime dependencies

Hyprland 0.55+, Rust/Cargo, a C/C++ compiler, `pkgconf`, GTK3,
`gtk-layer-shell`, NetworkManager/libnm, WirePlumber (`wpctl`), Fcitx 5 core
development headers, Dunst, Rofi 2, Blueberry, `powerprofilesctl`, and `jq`.

## Install

Run `./install.sh`, then log out and back in. The installer copies only the
tracked configuration, builds the optimized bar, and installs the two local
Fcitx addons. Hyprland starts `~/.config/nixie-shell/start-ui.sh`; Waybar and
Eww are not part of this setup.
