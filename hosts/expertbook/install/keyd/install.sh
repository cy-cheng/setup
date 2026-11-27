#!/bin/bash
# Copilot key -> Super (keyd). Run as root (pkexec bash install.sh). Needs: yay -S keyd
set -euo pipefail
cd "$(dirname "$0")"
install -Dm644 default.conf /etc/keyd/default.conf
# Append, never overwrite: this file also holds the touchpad fix (fixes/touchpad-fix.sh).
Q=/etc/libinput/local-overrides.quirks
grep -qs '^\[keyd virtual keyboard\]' "$Q" || { mkdir -p /etc/libinput; { echo; cat keyd.quirks; } >> "$Q"; }
systemctl enable keyd.service
systemctl restart keyd.service
echo done
