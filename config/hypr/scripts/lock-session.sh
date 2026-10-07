#!/usr/bin/env bash

set -u

hyprlock_running() {
    while IFS= read -r state; do
        case "$state" in
            Z* | "") ;;
            *) return 0 ;;
        esac
    done < <(ps -C hyprlock -o stat= 2>/dev/null)
    return 1
}

# Ask Hyprland rather than trusting a running hyprlock: one hung after
# unlocking and, for 14 hours, turned every lock request into a no-op.
lock_is_active() {
    local locked
    if locked="$(hyprctl locked 2>/dev/null)"; then
        [[ $locked == true ]]
    else
        hyprlock_running
    fi
}

# A hyprlock that has run for a few seconds without locking the session is
# hung. Younger ones are still starting, for example from a concurrent request.
kill_stale_hyprlock() {
    local pid age
    local -a stale=()
    while read -r pid age; do
        if (( age >= 5 )); then
            stale+=("$pid")
        fi
    done < <(ps -C hyprlock -o pid=,etimes= 2>/dev/null)
    (( ${#stale[@]} )) || return 0

    kill -TERM "${stale[@]}" 2>/dev/null
    for _ in {1..20}; do
        kill -0 "${stale[@]}" 2>/dev/null || return 0
        sleep 0.05
    done
    kill -KILL "${stale[@]}" 2>/dev/null
    sleep 0.1
}

if lock_is_active; then
    exit 0
fi

kill_stale_hyprlock

# Detach Hyprlock so hypridle's pre-sleep hook can return and release its
# inhibitor after the lock process has had time to claim the session.
if ! hyprlock_running; then
    setsid -f hyprlock --grace 0 --immediate-render </dev/null >/dev/null 2>&1
fi

for _ in {1..40}; do
    if lock_is_active; then
        sleep 0.25
        lock_is_active
        exit $?
    fi
    sleep 0.05
done

exit 1
