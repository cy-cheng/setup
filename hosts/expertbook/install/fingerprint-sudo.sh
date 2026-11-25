#!/bin/bash
# Let sudo and polkit popups (pkexec, the shell's authentication dialog) accept a
# fingerprint (password still works: Ctrl+C / wait 10 s; the dialog shows the field).
# Run with: sudo bash ~/setup/hosts/expertbook/install/fingerprint-sudo.sh        (undo: sudo bash ~/setup/hosts/expertbook/install/fingerprint-sudo.sh undo)
# Safety: keep a second terminal open with `sudo -s` while you test, so a
# mistake can't lock you out of sudo.
set -euo pipefail
LINE='auth		sufficient	pam_fprintd.so max-tries=2 timeout=10'
# polkit's PAM file lives in /usr/lib/pam.d; an /etc copy overrides it.
[ -e /etc/pam.d/polkit-1 ] || cp /usr/lib/pam.d/polkit-1 /etc/pam.d/polkit-1

for F in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
    if [ "${1:-}" = undo ]; then
        sed -i '/pam_fprintd\.so/d' "$F"; echo "Fingerprint removed from $F."; continue
    fi
    cp -n "$F" "$F.bak-before-fprint"
    if grep -q 'pam_fprintd\.so' "$F"; then
        echo "$F: already enabled."
    else
        sed -i "1a $LINE" "$F"     # right after the "#%PAM-1.0" header, before the password rule
        echo "$F: enabled."
    fi
done
[ "${1:-}" = undo ] && exit 0
echo
echo "Test in a NEW terminal:  sudo -k; sudo true      and:  pkexec true   (touch the sensor)"
