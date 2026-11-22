#!/bin/bash
# Keep this laptop's configs in the repo.
#   bash sync-configs.sh pull   copy live files from ~ into hosts/expertbook/home/ (default)
#   bash sync-configs.sh push   copy repo files back into ~ (existing files saved as *.bak)
# Personal data is deliberately not listed: SSH config, Rime user dictionaries,
# images, fonts, sync-screenshots (has a server path), anything with credentials.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
store="$here/home"

FILES=(
    .config/hypr/hyprland.lua
    .config/hypr/hypridle.conf
    .config/hypr/hyprlock.conf
    .config/hypr/application-style.conf
    .config/hypr/scripts/lock-session.sh
    .config/dunst/dunstrc
    .config/fcitx5/config
    .config/fcitx5/profile
    .config/fcitx5/conf/classicui.conf
    .config/fcitx5/conf/chewing.conf
    .config/fcitx5/conf/notifications.conf
    .local/share/fcitx5/rime/default.custom.yaml
    .config/kitty/kitty.conf
    .config/fish/config.fish
    .config/fish/fish_plugins
    .config/fish/functions/rm-to-trash.fish
    .config/qt6ct/qt6ct.conf
    .config/gtk-3.0/settings.ini
    .config/gtk-4.0/settings.ini
    .config/chrome-flags.conf
    .config/electron-flags.conf
    .config/code-flags.conf
    .config/discord-flags.conf
    .config/slack-flags.conf
    .local/bin/brightness
    .local/bin/charge-limit
    .local/bin/display-mode
    .local/bin/start-fcitx
    .local/bin/nixie-focus
    .local/share/dbus-1/services/org.knopwob.dunst.service
    .config/quickshell/shell.qml
    .config/quickshell/services/Theme.qml
    .config/quickshell/services/Sys.qml
    .config/quickshell/services/Notifs.qml
    .config/quickshell/services/Panels.qml
    .config/quickshell/modules/Background.qml
    .config/quickshell/modules/TubeGlow.qml
    .config/quickshell/modules/Frame.qml
    .config/quickshell/modules/Reserve.qml
    .config/quickshell/modules/BarContent.qml
    .config/quickshell/modules/RailContent.qml
    .config/quickshell/modules/DockTile.qml
    .config/quickshell/modules/DockWindow.qml
    .local/state/nixie-dock.json
    .config/quickshell/modules/Island.qml
    .config/quickshell/modules/Icon.qml
    .config/quickshell/modules/Label.qml
    .config/quickshell/modules/Ring.qml
    .config/quickshell/modules/Tip.qml
    .config/quickshell/modules/WifiPanel.qml
    .config/quickshell/modules/Launcher.qml
    .config/quickshell/modules/BluetoothPanel.qml
    .config/quickshell/modules/Popups.qml
    .config/quickshell/modules/Centre.qml
    .config/quickshell/modules/NotifCard.qml
    .local/bin/trash-prune-prompt
)

case "${1:-pull}" in
    pull)
        for f in "${FILES[@]}"; do
            if [ -e "$HOME/$f" ]; then
                install -D -m "$(stat -c %a "$HOME/$f")" "$HOME/$f" "$store/$f"
            else
                echo "missing (skipped): ~/$f"
            fi
        done
        echo "Pulled ${#FILES[@]} paths into $store" ;;
    push)
        for f in "${FILES[@]}"; do
            [ -e "$store/$f" ] || continue
            [ -e "$HOME/$f" ] && ! cmp -s "$store/$f" "$HOME/$f" && cp -a "$HOME/$f" "$HOME/$f.bak"
            install -D -m "$(stat -c %a "$store/$f")" "$store/$f" "$HOME/$f"
        done
        echo "Pushed configs into ~ (changed files kept as *.bak)" ;;
    *) echo "usage: $0 [pull|push]" >&2; exit 2 ;;
esac
