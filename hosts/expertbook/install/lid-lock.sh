#!/bin/bash
# Closing the lid locks the session instead of suspending (on battery and on AC).
# Run with: sudo bash ~/setup/hosts/expertbook/install/lid-lock.sh
set -euo pipefail
install -d /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/50-lid-lock.conf <<'EOF'
[Login]
# Lock (hypridle runs hyprlock) instead of suspending when the lid closes.
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore
EOF
# Reload without restarting logind (a restart would end your session).
systemctl reload systemd-logind
echo "Done: closing the lid now locks the screen."
