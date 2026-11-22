#!/bin/bash
# Let sudo accept a fingerprint (password still works: Ctrl+C or wait 10 s).
# Run with: sudo bash ~/setup/hosts/expertbook/install/fingerprint-sudo.sh        (undo: sudo bash ~/setup/hosts/expertbook/install/fingerprint-sudo.sh undo)
# Safety: keep a second terminal open with `sudo -s` while you test, so a
# mistake can't lock you out of sudo.
set -euo pipefail
F=/etc/pam.d/sudo
LINE='auth		sufficient	pam_fprintd.so max-tries=2 timeout=10'

if [ "${1:-}" = undo ]; then
    sed -i '/pam_fprintd\.so/d' "$F"
    echo "Fingerprint removed from sudo."
    exit 0
fi

cp -n "$F" "$F.bak-before-fprint"
if grep -q 'pam_fprintd\.so' "$F"; then
    echo "Already enabled."
else
    # Insert right after the "#%PAM-1.0" header, before the password rule.
    sed -i "1a $LINE" "$F"
fi
cat "$F"
echo
echo "Test in a NEW terminal:  sudo -k; sudo true   (touch the sensor)"
