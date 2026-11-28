#!/bin/bash
# Touchpad tap guard. Run as root: pkexec bash install.sh
# Change the pause: edit TAP_GUARD_SECONDS in tap-guard.service, re-run this.
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 tap-guard /usr/local/bin/tap-guard
install -Dm644 tap-guard.service /etc/systemd/system/tap-guard.service
systemctl daemon-reload
systemctl enable tap-guard.service
systemctl restart tap-guard.service
echo done
