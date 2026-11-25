#!/bin/bash
# Automatic timezone: NetworkManager runs 90-auto-timezone whenever a network comes up;
# it asks ipinfo.io (fallback ipwho.is) for the timezone of the Wi-Fi/Ethernet uplink's
# public IP — bypassing a full-tunnel VPN — and sets it with timedatectl.
# (GeoClue-based tools don't work here: GeoClue refuses clients without a desktop agent.)
# Run as your user:  bash ~/setup/hosts/expertbook/install/timezone/install.sh
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not root."; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
if [ -t 0 ]; then as_root=sudo; else as_root=pkexec; fi
$as_root install -m 755 "$here/90-auto-timezone" /etc/NetworkManager/dispatcher.d/90-auto-timezone
echo "Installed. It runs on the next network change (log: journalctl -t auto-timezone)."
