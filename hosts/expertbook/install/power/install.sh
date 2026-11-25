#!/bin/bash
# Battery/power setup for the ExpertBook. Run as root (e.g. pkexec bash install.sh).
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 power-profile-bridge /usr/local/libexec/power-profile-bridge
install -Dm644 power-profile-bridge.service /etc/systemd/system/power-profile-bridge.service
install -Dm644 ppd-block-platform.conf /etc/systemd/system/power-profiles-daemon.service.d/block-platform.conf
install -Dm644 90-battery.conf /etc/sysctl.d/90-battery.conf
install -Dm644 wifi-powersave.conf /etc/NetworkManager/conf.d/wifi-powersave.conf
install -Dm644 50-lid-sleep.conf /etc/systemd/logind.conf.d/50-lid-sleep.conf
rm -f /etc/systemd/logind.conf.d/50-lid-lock.conf     # old: lid only locked, back when sleep hung
install -Dm644 90-sleep.conf /etc/systemd/sleep.conf.d/90-sleep.conf
install -Dm755 touchpad-wake /usr/lib/systemd/system-sleep/touchpad-wake
install -Dm644 xe-no-lobf.service /etc/systemd/system/xe-no-lobf.service
install -Dm644 upower-hibernate.conf /etc/UPower/UPower.conf.d/90-hibernate.conf
systemctl daemon-reload
systemctl disable power-profile-bridge.service 2>/dev/null || true
systemctl enable --now power-profile-bridge.service
systemctl restart power-profile-bridge.service
sysctl -q --system
# No blanket PCI runtime-PM rule: forcing every device to "auto" (incl. the NVMe
# controller) made hibernation hang on 2026-11-23. Remove it if an old install left it.
rm -f /etc/udev/rules.d/50-runtime-pm.rules
udevadm control --reload
nmcli general reload conf 2>/dev/null || true
systemctl restart upower.service
systemctl enable --now xe-no-lobf.service
systemctl reload systemd-logind     # not restart: that would end the session
echo done
