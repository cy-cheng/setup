#!/usr/bin/env bash
# Installs the root-owned files under system/ and applies what changed.
# install.sh runs it through pkexec, so all system changes share one prompt.
#
#   install-system.sh          install and reload (as root)
#   install-system.sh --check  exit 0 when everything is in place (any user)
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

files=(
    usr/local/libexec/nixie-touchpad-recover:0755
    etc/systemd/system/nixie-touchpad-recover@.service:0644
    etc/systemd/system/nixie-touchpad-sleep.service:0644
    etc/systemd/system/nixie-touchpad-watchdog.service:0644
    usr/share/polkit-1/rules.d/50-nixie-touchpad.rules:0644
    etc/udev/rules.d/99-nixie-touchpad-power.rules:0644
    etc/systemd/logind.conf.d/90-nixie-power-button.conf:0644
)
# The old resume hook ran recovery inside systemd-sleep, delaying resume; it is
# replaced by nixie-touchpad-sleep.service.
obsolete=(/usr/lib/systemd/system-sleep/nixie-touchpad-recover)
units=(nixie-touchpad-sleep.service nixie-touchpad-watchdog.service)

changed=()
for entry in "${files[@]}"; do
    if ! cmp -s -- "$source_dir/${entry%:*}" "/${entry%:*}"; then
        changed+=("$entry")
    fi
done
stale=()
for path in "${obsolete[@]}"; do
    if [[ -e $path ]]; then
        stale+=("$path")
    fi
done

changed_matching() { # GLOB
    local entry
    for entry in "${changed[@]}"; do
        [[ ${entry%:*} == $1 ]] && return 0
    done
    return 1
}

if [[ ${1:-} == --check ]]; then
    (( ${#changed[@]} == 0 && ${#stale[@]} == 0 )) &&
        systemctl is-enabled --quiet "${units[@]}" &&
        systemctl is-active --quiet nixie-touchpad-watchdog.service
    exit
fi

if (( EUID != 0 )); then
    printf 'install-system.sh must run as root\n' >&2
    exit 77
fi

for entry in "${changed[@]}"; do
    install -D -m "${entry##*:}" -- "$source_dir/${entry%:*}" "/${entry%:*}"
    printf 'Installed /%s\n' "${entry%:*}"
done
for path in "${stale[@]}"; do
    rm -f -- "$path"
    printf 'Removed %s\n' "$path"
done

if changed_matching 'etc/systemd/system/*'; then
    systemctl daemon-reload
fi
if changed_matching 'etc/udev/*'; then
    udevadm control --reload-rules
fi
if changed_matching 'etc/systemd/logind.conf.d/*'; then
    systemctl reload systemd-logind.service
fi

systemctl enable --quiet "${units[@]}"
# The watchdog runs the helper, so restart it to pick up a new version.
if changed_matching 'usr/local/libexec/*' || changed_matching '*watchdog*' ||
    ! systemctl is-active --quiet nixie-touchpad-watchdog.service; then
    systemctl restart nixie-touchpad-watchdog.service
fi
