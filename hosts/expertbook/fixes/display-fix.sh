#!/bin/bash
# Display options from github.com/burakgon/asus-expertbook-linux (display-fix),
# the known-good set for the ExpertBook B9406CAA on the xe driver:
#   xe.enable_dpcd_backlight=2  VESA DPCD backlight interface
#   xe.enable_panel_replay=0    no Panel Replay
#   xe.enable_psr=1             PSR1 only (PSR2 / selective update cause artifacts on updates)
# Run with: sudo bash ~/setup/hosts/expertbook/fixes/display-fix.sh        (then reboot)
#           sudo bash ~/setup/hosts/expertbook/fixes/display-fix.sh nopsr  (same, but panel self-refresh fully off)
#           sudo bash ~/setup/hosts/expertbook/fixes/display-fix.sh undo   (back to only xe.enable_dpcd_backlight=1)
set -e
F=/etc/default/grub
cp -n "$F" "$F.bak-before-display-fix"

# Remove any previous xe.* display options, then add the requested set.
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { s/ ?\bxe\.enable_(dpcd_backlight|panel_replay|psr)=[0-9-]+//g }' "$F"
if [ "${1:-}" = undo ]; then
    opts="xe.enable_dpcd_backlight=1"
elif [ "${1:-}" = nopsr ]; then
    # Self-refresh fully off: fixes residual flicker on small rapid updates, costs a bit of battery
    opts="xe.enable_dpcd_backlight=2 xe.enable_panel_replay=0 xe.enable_psr=0"
else
    opts="xe.enable_dpcd_backlight=2 xe.enable_panel_replay=0 xe.enable_psr=1"
fi
sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 $opts\"/" "$F"
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { s/ +/ /g; s/ +"/"/; s/=" +/="/ }' "$F"
grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$F"

grub-mkconfig -o /boot/grub/grub.cfg
echo
echo "Done. Reboot, then check: sudo bash ~/setup/hosts/expertbook/diag/psr-test.sh   (expect 'PSR mode: PSR1 enabled')"
