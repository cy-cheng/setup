#!/bin/bash
# Build the Nixie Fcitx add-ons (candidate window + status) into ~/.local.
# Run as your normal user: bash fcitx-nixie-setup.sh ; ~/.local/bin/start-fcitx uses them.
set -euo pipefail
src="$HOME/setup/config/nixie-shell"
lib="$HOME/.local/lib/fcitx5"; addon="$HOME/.local/share/fcitx5/addon"
mkdir -p "$lib" "$addon"
c++ -std=c++20 -O3 -s -shared -fPIC "$src/backend/fcitx-nixie-ui.cpp" "$src/backend/fcitx-wayland-popup.cpp" \
    -o "$lib/nixieui.so" $(pkg-config --cflags --libs Fcitx5Core pangocairo wayland-client)
c++ -std=c++20 -O3 -s -shared -fPIC "$src/backend/fcitx-nixie-addon.cpp" \
    -o "$lib/nixiestatus.so" $(pkg-config --cflags --libs Fcitx5Core)
install -m644 "$src/fcitx/nixieui.conf" "$src/fcitx/nixiestatus.conf" "$addon/"
"$HOME/.local/bin/start-fcitx" >/dev/null 2>&1   # fcitx5 -d keeps the pipe open otherwise
echo "Fcitx restarted with the Nixie candidate window."
