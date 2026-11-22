# ASUS ExpertBook B9406CAA

Machine-specific setup for this laptop (Panther Lake, `xe` driver, BOE OLED panel).
Install scripts run as your normal user unless their header says `sudo`.

| Folder | Script | What it does |
|---|---|---|
| `install/` | `system-setup.sh` | Core system: audio firmware, GPU media, Bluetooth, zram, fwupd, Fcitx5, Quickshell, Tailscale, themes |
| | `install-apps.sh` | Everyday apps (Firefox, Chrome, Discord, Slack, Zoom, …) + Wayland flags |
| | `greeter-setup.sh` | Graphical login: greetd + ReGreet in a minimal Hyprland (`greeter/`) |
| | `lock-login-setup.sh` | First login setup (tuigreet, fprintd, fingerprint stay-awake rule) |
| | `fingerprint-sudo.sh` | sudo accepts a fingerprint (password via Ctrl+C) |
| | `lid-lock.sh` | Closing the lid locks instead of suspending |
| | `fcitx-nixie-setup.sh` | Builds the Nixie Fcitx candidate window (7-item row, Down = 5x5 grid, A-Y select) |
| | `fish-prompt.fish` | Nixie colours for the tide prompt and fish syntax highlighting |
| | `fonts-setup.sh` | Unbounded (UI) + Material Symbols (icons) for the Nixie shell |
| | `dev-power-setup.sh` | Dev toolchains (uv, Rust, clang, Verilog/EDA) + thermald, power-profile bridge, 80% charge limit (`power/`) |
| `install/power/` | `90-power-key-menu.conf` | logind ignores the power key so it opens the shell's power menu (copy to `/etc/systemd/logind.conf.d/`) |
| `fixes/` | `display-fix.sh` | Kernel options for the display; `nopsr` is the current setting |
| | `reboot-fix.sh` | `reboot=efi` for reboots hanging after "Rebooting." |
| | `touchpad-fix.sh` | libinput quirk for the PixArt 093A:4F05 touchpad |
| | `backlight-fix.sh` | Superseded by `display-fix.sh` |
| `diag/` | `psr-test.sh` | Panel self-refresh status (`off` is unsafe with PSR1, refuses) |
| | `touchpad-diag.sh` | libinput diagnostics |

`PLAN.md` is the running setup plan and decision log.

## Configs

`home/` mirrors this laptop's dotfiles (Hyprland, hypridle/hyprlock, Quickshell, Fcitx5,
kitty, fish, GTK/Qt theming, Electron/Chrome Wayland flags, `~/.local/bin` helpers).

- `bash sync-configs.sh pull` copies the live files from `~` into `home/` (run before committing).
- `bash sync-configs.sh push` installs them into `~` on a fresh setup (changed files kept as `*.bak`).

## Nixie shell (`~/.config/quickshell`)

Quickshell 0.3, started by Hyprland (`qs -d -n`); it also owns desktop notifications
(`~/.local/share/dbus-1/services/org.freedesktop.Notifications.service`).

| File | Role |
|---|---|
| `shell.qml` | One instance of every window below per screen |
| `services/Theme.qml` | Colours, fonts (Unbounded, Material Symbols), sizes |
| `services/Sys.qml` | Power profile (+ power saver on battery), input method, CPU, memory, brightness, keep-awake |
| `services/Notifs.qml` | Notification server: tiers, per-app rules, history, focus mode |
| `services/Vpn.qml` | NetworkManager VPN connections (nmcli, refreshed on `nmcli monitor` events) |
| `services/Panels.qml` | Which drop-down is open (Wi-Fi, Bluetooth, launcher, clipboard, power, dashboard) |
| `modules/Background.qml` + `TubeGlow.qml` | Nixie divergence-meter wallpaper |
| `modules/Reserve.qml`, `Frame.qml` | Screen frame and the space it reserves |
| `modules/BarContent.qml` + `Island.qml`, `Ring.qml`, `Icon.qml`, `Label.qml`, `Tip.qml` | Bar: workspaces, clock, tray, status rings |
| `modules/DockWindow.qml` + `DockContent.qml`, `DockTile.qml` | Right-edge dock (rest the pointer 0.7 s, or Super+Shift+D to pin) |
| `modules/Popups.qml`, `Centre.qml`, `NotifCard.qml` | Notification popups and the centre (slides in from the right, Super+N) |
| `modules/Dashboard.qml` + `DashGauge.qml`, `DashToggle.qml` | Drawer under the clock (click it or Super+A): media, gauges, quick toggles |
| `modules/Launcher.qml`, `Clipboard.qml` | Super+R apps / calculator / commands; Super+V clipboard history |
| `modules/WifiPanel.qml`, `BluetoothPanel.qml`, `PowerMenu.qml`, `Osd.qml` | Wi-Fi + VPN panel, Bluetooth panel, power menu, volume/brightness OSD |

IPC: `qs ipc call <target> <fn>` with `panels toggle <name>`, `notifs toggle|focus|clear`,
`dock toggle`, `power cycle|set <profile>`, `awake toggle`, `vpn list|toggle <name>`.

Not stored here on purpose: SSH config, Rime user dictionaries, images, fonts and
anything with credentials. Neovim lives in its own repo (`cy-cheng/nvim`, branch `agent`).
