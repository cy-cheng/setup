#!/usr/bin/env bash

set -u

lock_is_active() {
    while IFS= read -r state; do
        case "$state" in
            Z* | "") ;;
            *) return 0 ;;
        esac
    done < <(ps -C hyprlock -o stat= 2>/dev/null)
    return 1
}

if lock_is_active; then
    exit 0
fi

# Detach Hyprlock so hypridle's pre-sleep hook can return and release its
# inhibitor after the lock process has had time to claim the session.
setsid -f hyprlock --grace 0 --immediate-render </dev/null >/dev/null 2>&1

for _ in {1..40}; do
    if lock_is_active; then
        sleep 0.25
        lock_is_active
        exit $?
    fi
    sleep 0.05
done

exit 1
