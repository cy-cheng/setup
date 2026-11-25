#!/bin/bash
# Core system for the ExpertBook B9406CAA. Run as your normal user:
#   bash ~/setup/hosts/expertbook/install/system-setup.sh        (it calls sudo itself)
set -euo pipefail
if [ "$EUID" -eq 0 ]; then
    echo "Run as your normal user: bash ~/setup/hosts/expertbook/install/system-setup.sh" >&2
    exit 1
fi

PKGS=(
    # Audio: Intel SOF firmware (speakers/mics need it), ALSA/JACK through PipeWire
    sof-firmware pipewire-alsa pipewire-jack alsa-utils
    # GPU: hardware video decode (VA-API) and Vulkan for Intel Xe3
    intel-media-driver vulkan-intel libva-utils
    # Bluetooth
    bluez bluez-utils
    # Power, firmware, swap
    power-profiles-daemon fwupd zram-generator
    # Desktop basics: media keys, keyring, user folders
    playerctl gnome-keyring seahorse xdg-user-dirs
    # The new desktop shell (bar, dock, notifications, launcher)
    quickshell
    # Chinese/Japanese input (configs come from the setup repo)
    fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool fcitx5-chewing fcitx5-rime fcitx5-mozc
    # Screenshots, colour picker, night light, clipboard history
    hyprshot hyprpicker cliphist
    # Fonts: emoji, icon glyphs
    noto-fonts-emoji ttf-nerd-fonts-symbols
    # Look: dark GTK3 theme matching libadwaita, icon theme, Qt theming
    adw-gtk-theme papirus-icon-theme qt6ct
    # CLI
    man-db man-pages btop fastfetch github-cli git-lfs
    # Networking between your machines (the arch machine uses it too)
    tailscale
)
sudo pacman -S --needed "${PKGS[@]}"
yay -S --needed blueberry # Bluetooth manager (AUR); the Nixie bar opens it

# zram swap: compressed swap in RAM, half of memory
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

sudo systemctl enable --now \
    systemd-timesyncd.service \
    fstrim.timer \
    bluetooth.service \
    power-profiles-daemon.service \
    tailscaled.service
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service || true

# Per-user: audio session, standard folders
systemctl --user restart wireplumber pipewire pipewire-pulse || true
xdg-user-dirs-update

# Dark theme + amber accent for GTK apps (Qt reads ~/.config/qt6ct/qt6ct.conf)
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface accent-color 'orange'

echo
echo "Done. A reboot makes sure the audio firmware is picked up."
echo "Tailscale: run 'sudo tailscale up' when you want to join your tailnet."
