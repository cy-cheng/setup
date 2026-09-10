#!/usr/bin/env bash
set -euo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if ! pgrep -x fcitx5 >/dev/null; then
    setsid --fork /home/brine/.config/nixie-shell/start-fcitx.sh \
        </dev/null >>"$runtime_dir/nixie-fcitx.log" 2>&1
fi
for _ in {1..50}; do
    if busctl --user --list --no-pager 2>/dev/null | grep -q 'org.fcitx.Fcitx5'; then break; fi
    sleep 0.05
done
exec /home/brine/.config/nixie-shell/start.sh
