#!/bin/bash
# Login screen (greetd + tuigreet) and fingerprint reader (fprintd).
# Run with: sudo bash ~/setup/hosts/expertbook/install/lock-login-setup.sh
# Takes effect at next boot; your current Hyprland session is not touched.
set -euo pipefail

pacman -S --needed --noconfirm greetd greetd-tuigreet fprintd

# --- greetd: text-mode login screen on tty1, starts Hyprland -----------------
install -d /etc/greetd
[ -e /etc/greetd/config.toml ] && cp -n /etc/greetd/config.toml /etc/greetd/config.toml.orig
cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
# Remembers the last user and session; F3 opens the session list
# (Hyprland, Hyprland via uwsm, ... from /usr/share/wayland-sessions).
command = "tuigreet --time --remember --remember-session --asterisks --cmd start-hyprland"
user = "greeter"
EOF
systemctl enable greetd.service

# --- Fingerprint: FocalTech FT9349 (2808:a97a) -------------------------------
# Supported by libfprint's focaltech_moc driver, but USB autosuspend can leave
# it unresponsive, so keep it powered.
cat >/etc/udev/rules.d/99-fprint-ft9349-no-autosuspend.rules <<'EOF'
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="2808", ATTR{idProduct}=="a97a", ATTR{power/control}="on"
EOF
udevadm control --reload
udevadm trigger --subsystem-match=usb --attr-match=idVendor=2808 --action=change

echo
echo "Done."
echo "Next, as yourself (no sudo):  fprintd-enroll    (repeat with -f left-index-finger etc.)"
echo "Then reboot to get the new login screen."
