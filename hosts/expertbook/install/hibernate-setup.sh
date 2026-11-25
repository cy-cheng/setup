#!/bin/bash
# Hibernate (suspend-to-disk) for this laptop, as the replacement for sleep (s2idle never
# resumed here — see PLAN.md). Creates a 32 GB swap file the size of RAM (zram stays the
# preferred swap for normal use) and points the kernel at it so a boot can restore.
#
# Run as your normal user (it uses sudo for the system steps):
#   bash ~/setup/hosts/expertbook/install/hibernate-setup.sh
# Then reboot once and test:  systemctl hibernate   (power button wakes it; ~20 s)
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not root (sudo is used where needed)."; exit 1; }

swapfile=/swapfile
size=32G            # >= RAM (30 GiB) so a full hibernate image always fits

# 1. Swap file on the ext4 root, lower priority than zram so it's only used for hibernation.
if [ ! -f "$swapfile" ]; then
    echo "Creating $size swap file at $swapfile…"
    sudo mkswap -U clear --size "$size" --file "$swapfile"
fi
if ! grep -q "^$swapfile " /etc/fstab; then
    echo "$swapfile none swap defaults,pri=-2 0 0" | sudo tee -a /etc/fstab >/dev/null
fi
swapon --show=NAME --noheadings | grep -qx "$swapfile" || sudo swapon -p -2 "$swapfile"

# 2. Tell the kernel where the image lives: resume=<root fs UUID> resume_offset=<file offset>.
#    (systemd's initramfs can also find it via an EFI variable; this makes it explicit.)
uuid=$(findmnt -no UUID -T "$swapfile")
offset=$(sudo filefrag -v "$swapfile" | awk '$1=="0:" {sub(/\.\./, "", $4); print $4; exit}')
[ -n "$uuid" ] && [ -n "$offset" ] || { echo "Could not determine UUID/offset"; exit 1; }
args="resume=UUID=$uuid resume_offset=$offset"
echo "Kernel arguments: $args"

grub=/etc/default/grub
sudo cp -n "$grub" "$grub.bak-hibernate"
# Replace any old resume= / resume_offset= and append the new ones.
sudo sed -i -E \
    -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ ?resume(_offset)?=[^ "]*//g' \
    -e "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"\$/ $args\"/" "$grub"
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub"
sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null

echo
echo "Done. Reboot, then test with:  systemctl hibernate"
echo "Wake it with the power button; you should be back where you were in ~20 s."
