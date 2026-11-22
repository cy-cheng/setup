# ASUS ExpertBook B9406CAA

Machine-specific setup for this laptop (Panther Lake, `xe` driver, BOE OLED panel).
Install scripts run as your normal user unless their header says `sudo`.

| Folder | Script | What it does |
|---|---|---|
| `install/` | `system-setup.sh` | Core system: audio firmware, GPU media, Bluetooth, zram, fwupd, Fcitx5, dunst, Quickshell, Tailscale, themes |
| | `install-apps.sh` | Everyday apps (Firefox, Chrome, Discord, Slack, Zoom, …) + Wayland flags |
| | `greeter-setup.sh` | Graphical login: greetd + ReGreet in a minimal Hyprland (`greeter/`) |
| | `lock-login-setup.sh` | First login setup (tuigreet, fprintd, fingerprint stay-awake rule) |
| | `fingerprint-sudo.sh` | sudo accepts a fingerprint (password via Ctrl+C) |
| | `lid-lock.sh` | Closing the lid locks instead of suspending |
| | `fonts-setup.sh` | Unbounded (UI) + Material Symbols (icons) for the Nixie shell |
| | `dev-power-setup.sh` | Dev toolchains (uv, Rust, clang, Verilog/EDA) + thermald, power-profile bridge, 80% charge limit (`power/`) |
| `fixes/` | `display-fix.sh` | Kernel options for the display; `nopsr` is the current setting |
| | `reboot-fix.sh` | `reboot=efi` for reboots hanging after "Rebooting." |
| | `touchpad-fix.sh` | libinput quirk for the PixArt 093A:4F05 touchpad |
| | `backlight-fix.sh` | Superseded by `display-fix.sh` |
| `diag/` | `psr-test.sh` | Panel self-refresh status (`off` is unsafe with PSR1, refuses) |
| | `touchpad-diag.sh` | libinput diagnostics |

`PLAN.md` is the running setup plan and decision log.

## Configs

`home/` mirrors this laptop's dotfiles (Hyprland, hypridle/hyprlock, dunst, Fcitx5,
kitty, fish, GTK/Qt theming, Electron/Chrome Wayland flags, `~/.local/bin` helpers).

- `bash sync-configs.sh pull` copies the live files from `~` into `home/` (run before committing).
- `bash sync-configs.sh push` installs them into `~` on a fresh setup (changed files kept as `*.bak`).

Not stored here on purpose: SSH config, Rime user dictionaries, images, fonts and
anything with credentials. Neovim lives in its own repo (`cy-cheng/nvim`, branch `agent`).
