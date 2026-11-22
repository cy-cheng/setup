#!/bin/bash
# Fix: libinput treats every touch on the PixArt 093A:4F05 touchpad as a palm
# (bad pressure thresholds). Tell libinput to ignore pressure for this device.
# Run with: sudo bash ~/setup/hosts/expertbook/fixes/touchpad-fix.sh
set -e
Q=/etc/libinput/local-overrides.quirks
mkdir -p /etc/libinput

if grep -q 'MatchProduct=0x4F05' "$Q" 2>/dev/null; then
  echo "Quirk already present in $Q"
else
  cat >> "$Q" <<'EOF'

[ASUS ExpertBook B9406 PixArt Touchpad]
MatchUdevType=touchpad
MatchBus=i2c
MatchVendor=0x093A
MatchProduct=0x4F05
AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
EOF
  echo "Wrote quirk to $Q"
fi

echo; echo "== libinput now applies =="
libinput quirks list /dev/input/event10

# Re-probe the touchpad so Hyprland re-opens it with the new quirk (no relogin needed)
DEV=i2c-ASCP1D80:00
DRV=$(basename "$(readlink -f /sys/bus/i2c/devices/$DEV/driver)")
echo; echo "Rebinding $DEV on driver $DRV ..."
echo "$DEV" > /sys/bus/i2c/drivers/$DRV/unbind
sleep 1
echo "$DEV" > /sys/bus/i2c/drivers/$DRV/bind
sleep 1
echo "Done. Try the touchpad now."
