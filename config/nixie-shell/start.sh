#!/usr/bin/env bash
set -euo pipefail

# Fractional scaling is negotiated by GTK's Wayland backend. A session-wide
# integer GDK scale would misplace transient surfaces such as tooltips.
unset GDK_SCALE
unset GDK_DPI_SCALE

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nixie-shell"
binary="$config_dir/target/release/nixie-shell"
menu_source="$config_dir/backend/nm-menu.c"
menu_binary="$config_dir/backend/nm-menu"
addon_source="$config_dir/backend/fcitx-nixie-addon.cpp"
addon_binary="${XDG_DATA_HOME:-$HOME/.local/share}/../lib/fcitx5/nixiestatus.so"
addon_config="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon/nixiestatus.conf"
ui_source="$config_dir/backend/fcitx-nixie-ui.cpp"
ui_popup_source="$config_dir/backend/fcitx-wayland-popup.cpp"
ui_binary="${XDG_DATA_HOME:-$HOME/.local/share}/../lib/fcitx5/nixieui.so"
ui_config="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon/nixieui.conf"

if [[ ! -x "$menu_binary" || "$menu_source" -nt "$menu_binary" ]]; then
    cc -O3 -s "$menu_source" -o "$menu_binary" \
        $(pkg-config --cflags --libs libnm gtk+-3.0 gtk-layer-shell-0)
fi

if [[ ! -f "$ui_binary" || "$ui_source" -nt "$ui_binary" || "$ui_popup_source" -nt "$ui_binary" ]]; then
    mkdir -p "$(dirname "$ui_binary")" "$(dirname "$ui_config")"
    c++ -std=c++20 -O3 -s -shared -fPIC "$ui_source" "$ui_popup_source" \
        -o "$ui_binary" \
        $(pkg-config --cflags --libs Fcitx5Core pangocairo wayland-client)
    cp -- "$config_dir/fcitx/nixieui.conf" "$ui_config"
fi

if [[ ! -f "$addon_binary" || "$addon_source" -nt "$addon_binary" ]]; then
    mkdir -p "$(dirname "$addon_binary")" "$(dirname "$addon_config")"
    c++ -std=c++20 -O3 -s -shared -fPIC "$addon_source" -o "$addon_binary" \
        $(pkg-config --cflags --libs Fcitx5Core)
    cp -- "$config_dir/fcitx/nixiestatus.conf" "$addon_config"
fi

if [[ ! -x "$binary" || "$config_dir/Cargo.toml" -nt "$binary" || -n "$(find "$config_dir/src" -type f -newer "$binary" -print -quit)" ]]; then
    cargo build --release --manifest-path "$config_dir/Cargo.toml"
fi

exec "$binary" --config "$config_dir/config.toml"
