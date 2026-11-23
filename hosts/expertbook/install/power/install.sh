#!/bin/bash
# Battery/power setup for the ExpertBook. Run as root (e.g. pkexec bash install.sh).
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 power-profile-bridge /usr/local/libexec/power-profile-bridge
install -Dm644 power-profile-bridge.service /etc/systemd/system/power-profile-bridge.service
install -Dm644 ppd-block-platform.conf /etc/systemd/system/power-profiles-daemon.service.d/block-platform.conf
install -Dm644 50-runtime-pm.rules /etc/udev/rules.d/50-runtime-pm.rules
install -Dm644 90-battery.conf /etc/sysctl.d/90-battery.conf
install -Dm644 wifi-powersave.conf /etc/NetworkManager/conf.d/wifi-powersave.conf
systemctl daemon-reload
systemctl disable power-profile-bridge.service 2>/dev/null || true
systemctl enable --now power-profile-bridge.service
systemctl restart power-profile-bridge.service
sysctl -q --system
udevadm control --reload
for d in /sys/bus/pci/devices/*/power/control; do echo auto > "$d" 2>/dev/null || true; done
nmcli general reload conf 2>/dev/null || true
echo done
