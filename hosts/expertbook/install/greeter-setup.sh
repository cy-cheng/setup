#!/bin/bash
# Graphical login: greetd + ReGreet, hosted by a minimal Hyprland at scale 2.
# Run as your normal user (NOT with sudo):  bash ~/setup/hosts/expertbook/install/greeter-setup.sh
# Takes effect at the next boot / logout. If it ever fails to start,
# Ctrl+Alt+F2 gives a text login; `bash ~/setup/hosts/expertbook/install/greeter-setup.sh undo` reverts.
set -euo pipefail
if [ "$EUID" -eq 0 ]; then
    echo "Run as your normal user: bash ~/setup/hosts/expertbook/install/greeter-setup.sh" >&2
    exit 1
fi
src="$(cd "$(dirname "$0")" && pwd)/greeter"

if [ "${1:-}" = undo ]; then
    sudo cp /etc/greetd/config.toml.tuigreet /etc/greetd/config.toml
    echo "Back to tuigreet."
    exit 0
fi

# ReGreet + the theme it uses (dark GTK theme, Papirus icons; qt6ct for Qt apps)
# uwsm makes the "Hyprland (uwsm)" entry in the session list actually start.
yay -S --needed greetd-regreet adw-gtk-theme papirus-icon-theme qt6ct uwsm

sudo install -m 644 "$src/hyprland-greeter.lua" /etc/greetd/hyprland-greeter.lua
sudo install -m 644 "$src/regreet.toml" /etc/greetd/regreet.toml
sudo install -m 644 "$src/regreet.css" /etc/greetd/regreet.css
# The greeter user can't read your home, so the background gets its own copy.
sudo install -m 644 "$HOME/.config/hypr/data/lockscreen.jpg" /etc/greetd/background.jpg

# Keep the tuigreet config for `undo`, then point greetd at ReGreet.
[ -e /etc/greetd/config.toml.tuigreet ] || sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.tuigreet
sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
# start-hyprland is the supported launcher (plain `Hyprland` shows a warning).
command = "start-hyprland -- --config /etc/greetd/hyprland-greeter.lua"
user = "greeter"
EOF

# GTK apps you run yourself also get the dark theme + icons now that they exist.
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'

echo
echo "Done. Log out (Super+M) or reboot to see the new login screen."
