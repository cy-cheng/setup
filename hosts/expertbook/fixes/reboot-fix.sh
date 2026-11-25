#!/bin/bash
# Work around reboots that hang after "systemd-shutdown[1]: Rebooting."
# Sets the kernel's reboot method and shows kernel messages during shutdown.
# Run with: sudo bash ~/setup/hosts/expertbook/fixes/reboot-fix.sh [method]
#   method: efi (default), acpi, pci, kbd, triple — or "none" to remove reboot=
set -e
METHOD="${1:-efi}"
F=/etc/default/grub
cp -n "$F" "$F.bak-before-reboot-fix"

# Replace any previous reboot= and loglevel= values.
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ ?\breboot=[a-z,]+//; /^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ ?\bloglevel=[0-9]+//' "$F"
[ "$METHOD" != none ] && sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 reboot=$METHOD\"/" "$F"
# loglevel=5: show kernel warnings/notices on screen during shutdown (diagnostic).
sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")/\1loglevel=5 /' "$F"
# Drop "quiet" so shutdown messages are visible, then tidy spacing.
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { s/\bquiet\b//; s/ +/ /g; s/ +"/"/; s/=" +/="/ }' "$F"
grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$F"

grub-mkconfig -o /boot/grub/grub.cfg
echo
echo "Done. Reboot a few times to test (it only hangs sometimes)."
