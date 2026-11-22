#!/bin/bash
# Everyday apps. Run as your normal user (NOT with sudo): bash ~/setup/hosts/expertbook/install/install-apps.sh
# pacman asks for your password; yay builds AUR packages as you.
set -euo pipefail

if [ "$EUID" -eq 0 ]; then
    echo "Run this as your normal user: bash ~/setup/hosts/expertbook/install/install-apps.sh  (it calls sudo itself)" >&2
    exit 1
fi

# Official repos
OFFICIAL=(
    # browsers / chat
    firefox discord telegram-desktop
    # office, notes, mail, research
    libreoffice-fresh xournalpp obsidian thunderbird typst evince
    # media
    vlc mpv obs-studio gimp loupe
    # engineering
    kicad freecad
)

# AUR
AUR=(
    google-chrome
    slack-desktop
    zoom
    notion-app-electron
    visual-studio-code-bin
    anydesk-bin
)

sudo pacman -S --needed "${OFFICIAL[@]}"
yay -S --needed "${AUR[@]}"

# Native Wayland (sharp at 2x scaling) + Fcitx input for Chromium/Electron apps
mkdir -p ~/.config
flags='--ozone-platform-hint=auto
--enable-wayland-ime
--wayland-text-input-version=3'
for f in chrome-flags.conf electron-flags.conf code-flags.conf discord-flags.conf slack-flags.conf; do
    [ -e ~/.config/$f ] || printf '%s\n' "$flags" > ~/.config/$f
done

# Zoom: native Wayland instead of XWayland (XWayland apps are drawn at half resolution
# and stretched at 2x scaling). Zoom rewrites zoomus.conf on exit, so only edit it
# while Zoom is closed.
if [ -e ~/.config/zoomus.conf ] && ! pgrep -x zoom >/dev/null; then
    sed -i 's/^xwayland=true$/xwayland=false/' ~/.config/zoomus.conf
    grep -q '^enableWaylandShare=' ~/.config/zoomus.conf \
        || sed -i '/^\[General\]/a enableWaylandShare=true' ~/.config/zoomus.conf
fi
# Spotify (spotify-launcher): native Wayland too
[ -e ~/.config/spotify-launcher.conf ] || printf '%s\n' '[spotify]' \
    'extra_arguments = ["--enable-features=UseOzonePlatform", "--ozone-platform=wayland"]' \
    > ~/.config/spotify-launcher.conf

echo "Done."
