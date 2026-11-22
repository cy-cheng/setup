#!/bin/bash
# Development toolchains + battery/power tuning for the ExpertBook B9406CAA.
# Run as your normal user (NOT with sudo):
#   bash ~/setup/hosts/expertbook/install/dev-power-setup.sh
set -euo pipefail
if [ "$EUID" -eq 0 ]; then
    echo "Run as your normal user: bash $0" >&2
    exit 1
fi
here="$(cd "$(dirname "$0")" && pwd)"

# --- Development (no Docker) ----------------------------------------------------
# uv: Python projects/venvs; rustup: Rust; clang/lldb: C/C++ (clangd comes via Neovim/Mason);
# cmake, valgrind; Verilog/EDA: iverilog, yosys, gtkwave
yay -S --needed uv rustup cmake clang lldb valgrind iverilog yosys gtkwave
rustup default stable

# --- Power ------------------------------------------------------------------------
# thermald: Intel's thermal daemon (smoother throttling)
yay -S --needed thermald
sudo systemctl enable --now thermald.service

# power-saver / performance also switch the ASUS (quiet) and SoC (low-power) modes
sudo install -Dm755 "$here/power/power-profile-bridge" /usr/local/libexec/power-profile-bridge
sudo install -Dm644 "$here/power/power-profile-bridge.service" /etc/systemd/system/power-profile-bridge.service
sudo install -Dm644 "$here/power/ppd-block-platform.conf" /etc/systemd/system/power-profiles-daemon.service.d/block-platform.conf
sudo systemctl daemon-reload
sudo systemctl restart power-profiles-daemon.service
sudo systemctl enable --now power-profile-bridge.service

# Battery: stop charging at 80% (now and at every boot). `charge-limit 100` before travel.
sudo install -Dm644 "$here/power/99-battery-charge-limit.rules" /etc/udev/rules.d/99-battery-charge-limit.rules
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold >/dev/null

echo
echo "Done. Charge limit: $(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)%"
echo "Power profile: $(powerprofilesctl get)  (switch: powerprofilesctl set power-saver|balanced|performance)"
