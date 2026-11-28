# New laptop setup plan (ASUS ExpertBook B9406, Core Ultra 7 356H)

Source machine: `arch` (Zenbook UX3402ZA, 192.168.50.232). Desktop = Nixie repo
`github.com/cy-cheng/setup` (branch `agent/native-nixie-shell`).
Status: nothing installed yet. [x] = already on this laptop.

## 1. Core system
- [x] base linux linux-firmware intel-ucode grub efibootmgr sudo networkmanager
- base-devel git openssh man-db man-pages less unzip zip rsync wget usbutils
- sof-firmware (audio on Intel), intel-media-driver + vulkan-intel (GPU video/Vulkan)
- fwupd (BIOS/firmware updates), power-profiles-daemon, zram-generator, smartmontools
- bluez bluez-utils, pipewire-alsa pipewire-jack [x pipewire pipewire-pulse wireplumber]
- tailscale, iw
- DROP from arch: xf86-video-amdgpu/ati/nouveau, vulkan-radeon/nouveau, xorg-server/xinit,
  wireless_tools, wpa_supplicant (NM uses iwd/wpa anyway; decide), os-prober (if no dual boot)

## 2. Nixie desktop (what install.sh needs)
- [x] hyprland hypridle hyprlock xdg-desktop-portal-hyprland kitty (rofi, hyprpolkitagent removed)
- hyprpicker grim slurp python-pillow (screenshots: ~/.local/bin/shot) uwsm (no hyprsunset: the warm shader is always on) (dunst dropped: the Quickshell shell owns notifications)
- build deps: rustup (cargo), gtk3 gtk-layer-shell libpulse libnm jq curl geoclue pkgconf
- fcitx5 fcitx5-chewing fcitx5-rime fcitx5-mozc fcitx5-gtk fcitx5-qt fcitx5-configtool
- qt6-wayland qt5-wayland qt6ct, gnome-keyring + seahorse, xdg-utils
- Files: dolphin + xdg-desktop-portal-kde (Open/Save dialogs match Dolphin; portal pref in
  ~/.config/xdg-desktop-portal/hyprland-portals.conf), kio-extras ffmpegthumbs
  kdegraphics-thumbnailers breeze breeze-icons ark; exfatprogs (USB sticks). Thunar replaced.
- AUR: yay, input-remapper-git (mouse keys), blueberry
- Fonts: noto-fonts-emoji, ttf-cascadia-mono-nerd (kitty "CaskaydiaMono NF"),
  adwaita-fonts, otf-font-awesome [x noto-fonts noto-fonts-cjk]
  + copy private BO NX / TT Chocolates from arch:/usr/local/share/fonts
- DROP: waybar wofi eww ags/astal hyprpaper (superseded by Nixie), all KDE Plasma + GNOME bits,
  gdm AND sddm (pick one lighter login, see 6), neofetch (dead -> fastfetch)

## 3. Shell & CLI
- fish (+ fisher, tide, nvm.fish), zoxide, fzf, btop, zellij or tmux (arch has both; pick one)
- neovim + ripgrep fd tree-sitter-cli (telescope/treesitter need these), uv, github-cli, typst

## 4. Apps (pick)
firefox, google-chrome, visual-studio-code-bin, discord, libreoffice-fresh, obs-studio, gimp,
vlc, zathura(-pdf-poppler)/evince, xournalpp, remmina, onedrive-abraunegg, anydesk-bin,
KiCad (flatpak), freecad, spectacle?, qpwgraph, rpi-imager, platformio-core + platformio-core-udev (carcar)

## 5. Dev / EDA (pick)
docker docker-compose, dotnet-sdk, iverilog yosys gtkwave, postgresql, openmpi, cmake meson,
npm pnpm (or via nvm/mise), ruby, go, julia (juliaup), platformio

## 6. Things to improve (discussion)
1. arch's ~/.config/fish/config.fish has expired AWS session creds hardcoded — drop those
   lines when porting fish config (never commit them).
2. Dotfiles are split: Nixie in `setup`, nvim in `cy-cheng/nvim`, fish/kitty/zellij/git untracked.
   Proposal: add fish/kitty/zellij/git + a package list (pkglist.txt) to `setup`, and per-host
   files (this laptop's libinput quirk, touchscreen fix) under system/hosts/<name>.
3. Touchpad: drop Zenbook ELAN recovery units; keep libinput quirk for PixArt 093A:4F05.
   Keep mouse keys (Fn+F6) + power-button menu.
4. Touchscreen: Raydium is rejected by libinput (kernel reports min==max on ABS_X) — needs a fix.
5. Login: sddm/gdm pull in KDE/GNOME. Options: greetd+tuigreet, or tty autologin + `uwsm start`.
6. fish: `alias vim "uv run nvim"`, `nvm use latest` on every shell start (slow), manual ssh-agent
   -> consider mise for node, gnome-keyring/systemd ssh-agent.
7. Neovim: lazy.nvim, blink.cmp, mason+lspconfig, telescope, neo-tree, noice, copilot.vim AND
   codecompanion, two themes (catppuccin + tokyonight), barbar, lualine, typst-preview, markview.
   Ideas: native vim.lsp.config (0.11+), drop redundant theme, fzf-lua/snacks picker, etc.

## 7. Decisions so far (2026-11-22)
- Neovim: rebuilt, branch `agent` of cy-cheng/nvim (tokyonight + noice kept, no Copilot).
- Shell: fish (config ported, tide prompt pending). Login: greetd + tuigreet. Lock: hyprlock + hypridle (+ fingerprint).
- Notifications/shell: Quickshell. Tiers (Needs you / FYI / Quiet / System), per-app rules,
  attention rail permanently on the RIGHT edge, click → source window (not the arrival workspace).
- Reminder list: try Zed; projector/monitor config; agent session manager across machines.

## Sleep → hibernate (2026-11-22)
- s2idle suspend never resumed (log stops at `PM: suspend entry (s2idle)`; hard reboot). BIOS B9406CAA.304 is the latest. 2026-11-25: deep (S3) hangs too, even with an RTC alarm; pm_test freezer/devices pass, so it is the platform/firmware step, not a driver. Hibernate stays. FIXED 2026-11-25 by BIOS .312 (from asus.com via EZ Flash; fwupd didn't offer it): s2idle sleeps and wakes (keys, touchpad, lid, RTC). Screen flashed 2-3x on wake from eDP LOBF link retrains: xe-no-lobf.service.
- Replaced with hibernate: `install/hibernate-setup.sh` (32 GB /swapfile, GRUB resume=/resume_offset=). Verified: `systemctl hibernate` restores the session.
- hypridle: lock + screen off at 5 min; on battery sleep at 5.5 min. Lid (logind): on battery suspend-then-hibernate (hibernate after 2 h asleep, sleep.conf), on AC suspend. Touchpad wake is off only while the lid is closed (system-sleep/touchpad-wake). Shell: battery notices at 20/10/5 %, hibernate at <=5 % when away, 1 % regardless. Power menu: Lock · Sleep · Hibernate · …

## Timezone (2026-11-22)
- automatic-timezoned/GeoClue failed: GeoClue keeps clients "waiting for agent" without a GNOME/KDE location agent, even with an empty agent whitelist. Reverted and uninstalled.
- Now: NetworkManager dispatcher `install/timezone/90-auto-timezone` looks up the timezone of the physical uplink's IP (ipinfo.io, fallback ipwho.is; curl --interface so the EAILab VPN doesn't skew it). Verified UTC -> Asia/Taipei.
- Phone internet: `usbmuxd` (iPhone USB tethering via ipheth; phone must Trust the laptop + Personal Hotspot on). NM profile `nmcli connection add type ethernet con-name "iPhone USB" match.driver ipheth connection.metered yes` (wired metric beats Wi-Fi, so USB is preferred when plugged). Phone Wi-Fi hotspot "Brine" set `connection.metered yes`.
- Wi-Fi preference: `nmcli connection modify EAI_lab connection.autoconnect-priority 100`; ~/.local/bin/wifi-prefer (wifi-prefer.timer, user, every 2 min) switches to EAI_lab when it is in range at >=40% signal, since NM never leaves a working connection on its own.
- Copilot key (right of right Alt) = Super: keyd (`yay -S keyd`, then `pkexec bash install/keyd/install.sh`). It sends Super+Shift+F23 as a chord; keyd maps the chord to leftmeta. The keyd quirk (keyboard integration internal) is appended to /etc/libinput/local-overrides.quirks next to the touchpad fix, never overwriting it. Starting keyd mid-session breaks touchpad palm rejection until Hyprland restarts (libinput reads quirks once), so install it, then reboot.
- Touchpad palm taps: tap-guard (install/tap-guard, root service) turns tap-to-click off for TAP_GUARD_SECONDS (1.0) after each non-modifier key, via hyprctl eval hl.device(...). Measured 2026-11-28: pressure useless (taps 0-5, palms 0-37); palms land at x 200-520 / 3100-3500, inside libinput's fixed 8 % edge zone.
- Quickshell caches the timezone; Sys.qml tracks `date +%z` every 30 s and Sys.zoned() shifts the bar/dashboard/background/notification clocks.
- Removed unused packages: rofi, hyprpolkitagent, geoclue, automatic-timezoned, AUR -debug packages and leftover build tools (meson, gtk-doc, gobject-introspection, asar, python build tools).
