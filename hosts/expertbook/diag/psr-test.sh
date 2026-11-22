#!/bin/bash
# Live test for flicker caused by Panel Self Refresh / Panel Replay on eDP.
# Run with: sudo bash ~/setup/hosts/expertbook/diag/psr-test.sh off   -> disable PSR/Panel Replay now (until reboot)
#           sudo bash ~/setup/hosts/expertbook/diag/psr-test.sh on    -> back to driver default
#           sudo bash ~/setup/hosts/expertbook/diag/psr-test.sh       -> just show status
set -u
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug

dbg=$(ls -d /sys/kernel/debug/dri/*/eDP-1 2>/dev/null | head -1)
ctl=$(ls /sys/kernel/debug/dri/*/i915_edp_psr_debug 2>/dev/null | head -1)
[ -z "$ctl" ] && ctl=$(ls "$dbg"/i915_edp_psr_debug 2>/dev/null)

show() {
    for f in /sys/kernel/debug/dri/*/i915_edp_psr_status "$dbg"/i915_psr_status; do
        [ -r "$f" ] && { echo "--- $f"; head -8 "$f"; }
    done
}

case "${1:-status}" in
    off)
        # With xe.enable_psr=1 on the cmdline, this live write blanked the panel
        # (2026-11-22); hyprctl dpms off/on brought it back. Use the cmdline instead.
        if grep -q 'xe.enable_psr=1' /proc/cmdline && [ "${2:-}" != --force ]; then
            echo "Refusing: with xe.enable_psr=1 this blanks the screen. Set xe.enable_psr=0 in GRUB instead." >&2
            exit 1
        fi
        echo 0x1 > "$ctl" && echo "PSR/Panel Replay disabled (via $ctl)";;
    on)  echo 0x0 > "$ctl" && echo "PSR back to default (via $ctl)";;
esac
show
