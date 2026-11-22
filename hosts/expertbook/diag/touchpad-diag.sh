#!/bin/bash
# Touchpad diagnostics. Run with: sudo bash ~/setup/hosts/expertbook/diag/touchpad-diag.sh
# Output goes to ~/touchpad-diag.log (owned by you).
OUT=/home/brine/touchpad-diag.log
exec > "$OUT" 2>&1

echo "== lid switch (evdev) =="
evtest --query /dev/input/event0 EV_SW SW_LID; echo "lid_query_exit=$? (10 = CLOSED, 0 = open)"

echo; echo "== libinput list-devices =="
libinput list-devices

echo; echo "== libinput quirks for touchpad =="
for e in /dev/input/event*; do
  echo "-- $e"; libinput quirks list "$e"
done

echo; echo "== libinput debug-events (8s) — SWIPE/TAP THE TOUCHPAD NOW =="
echo -e '\a' > /dev/tty 2>/dev/null
echo ">>> Swipe and tap the touchpad for 8 seconds..." > /dev/tty 2>/dev/null
timeout 8 libinput debug-events --verbose
echo ">>> Done." > /dev/tty 2>/dev/null

chown brine:brine "$OUT"
