#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nixie-shell"
lib_dir="${XDG_DATA_HOME:-$HOME/.local/share}/../lib/fcitx5"
addon_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon"
mkdir -p "$lib_dir" "$addon_dir"

if [[ ! -f "$lib_dir/nixiestatus.so" || "$config_dir/backend/fcitx-nixie-addon.cpp" -nt "$lib_dir/nixiestatus.so" ]]; then
    c++ -std=c++20 -O3 -s -shared -fPIC "$config_dir/backend/fcitx-nixie-addon.cpp" \
        -o "$lib_dir/nixiestatus.so" $(pkg-config --cflags --libs Fcitx5Core)
fi
if [[ ! -f "$lib_dir/nixieui.so" || "$config_dir/backend/fcitx-nixie-ui.cpp" -nt "$lib_dir/nixieui.so" ]]; then
    c++ -std=c++20 -O3 -s -shared -fPIC "$config_dir/backend/fcitx-nixie-ui.cpp" \
        -o "$lib_dir/nixieui.so" $(pkg-config --cflags --libs Fcitx5Core)
fi
if [[ ! -f "$addon_dir/nixiestatus.conf" ]] || ! cmp -s "$config_dir/fcitx/nixiestatus.conf" "$addon_dir/nixiestatus.conf"; then cp -- "$config_dir/fcitx/nixiestatus.conf" "$addon_dir/nixiestatus.conf"; fi
if [[ ! -f "$addon_dir/nixieui.conf" ]] || ! cmp -s "$config_dir/fcitx/nixieui.conf" "$addon_dir/nixieui.conf"; then cp -- "$config_dir/fcitx/nixieui.conf" "$addon_dir/nixieui.conf"; fi

export FCITX_DATA_DIRS="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5"
export FCITX_ADDON_DIRS="$lib_dir:/usr/lib/fcitx5"
exec fcitx5 --enable=nixiestatus,nixieui --ui=nixieui
