#!/bin/bash
# Make the BOE NB140B91-M02 (OLED-style eDP panel) honour brightness changes:
# the xe driver's default PWM backlight path writes values the panel ignores,
# so switch to DPCD (AUX) backlight control. Takes effect after a reboot.
# Run with: sudo bash ~/setup/hosts/expertbook/fixes/backlight-fix.sh [mode]   (mode: 1 = enable [default], 3 = force Intel, 2 = force VESA)
set -e
MODE="${1:-1}"
F=/etc/default/grub
cp -n "$F" "$F.bak-before-backlight"

# Drop any previous value, then append the new one.
sed -i -E 's/ ?xe\.enable_dpcd_backlight=[0-9-]+//' "$F"
sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 xe.enable_dpcd_backlight=$MODE\"/" "$F"
# Temporarily show boot/shutdown messages (drop "quiet") to see where reboot hangs.
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ ?\bquiet\b//; /^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"[ ]+/"/' "$F"
grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$F"

grub-mkconfig -o /boot/grub/grub.cfg
echo
echo "Done. Reboot, then test the Fn brightness keys."
