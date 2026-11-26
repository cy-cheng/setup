#!/usr/bin/env bash
# After resume: restart hyprlock if the session is locked, so its fingerprint reader
# works again. fprintd is restarted around sleep (system-sleep/fprintd-reset: the sensor
# fails otherwise), and a running hyprlock never re-claims the device from the new
# fprintd ("Device was not claimed before use"). A fresh hyprlock claims it.
# SIGKILL, not SIGTERM: the session must stay locked in between; Hyprland keeps it
# locked and lets the new hyprlock take over (misc.allow_session_lock_restore).
pgrep -x hyprlock >/dev/null || exit 0
pkill -KILL -x hyprlock
for _ in {1..20}; do pgrep -x hyprlock >/dev/null || break; sleep 0.05; done
sleep 0.5      # let fprintd come back up
setsid -f hyprlock --immediate-render </dev/null >/dev/null 2>&1
