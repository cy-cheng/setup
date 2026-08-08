#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

check_font() {
    local query="$1" expected="$2" matched
    matched="$(fc-match -f '%{family}' "$query" 2>/dev/null || true)"
    if [[ "$matched" != *"$expected"* ]]; then
        printf 'Warning: divergence font %s is unavailable; a fallback will be used.\n' "$query" >&2
    fi
}

check_font "BO NX Medium" "BO NX"
check_font "TT Chocolates Trl ExtraLight" "TT Chocolates Trl"

install -d "$config_home" "$data_home"
cp -a -- "$repo_dir/config/." "$config_home/"
cp -a -- "$repo_dir/local/share/." "$data_home/"
chmod +x "$config_home/nixie-shell/start.sh" \
    "$config_home/nixie-shell/start-ui.sh" \
    "$config_home/nixie-shell/start-fcitx.sh" \
    "$config_home/nixie-shell/bin/"*

cargo build --release --manifest-path "$config_home/nixie-shell/Cargo.toml"

lib_dir="$data_home/../lib/fcitx5"
addon_dir="$data_home/fcitx5/addon"
install -d "$lib_dir" "$addon_dir"
c++ -std=c++20 -O3 -s -shared -fPIC \
    "$config_home/nixie-shell/backend/fcitx-nixie-addon.cpp" \
    -o "$lib_dir/nixiestatus.so" $(pkg-config --cflags --libs Fcitx5Core)
c++ -std=c++20 -O3 -s -shared -fPIC \
    "$config_home/nixie-shell/backend/fcitx-nixie-ui.cpp" \
    "$config_home/nixie-shell/backend/fcitx-wayland-popup.cpp" \
    -o "$lib_dir/nixieui.so" \
    $(pkg-config --cflags --libs Fcitx5Core pangocairo wayland-client)
install -m 0644 "$config_home/nixie-shell/fcitx/nixiestatus.conf" "$addon_dir/nixiestatus.conf"
install -m 0644 "$config_home/nixie-shell/fcitx/nixieui.conf" "$addon_dir/nixieui.conf"

printf 'Nixie setup installed. Log out and back in to start the new UI.\n'
